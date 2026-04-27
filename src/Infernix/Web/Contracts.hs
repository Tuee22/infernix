{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}

module Infernix.Web.Contracts
  ( EngineBinding (..),
    ErrorResponse (..),
    InferenceRequest (..),
    InferenceResult (..),
    ModelDescriptor (..),
    RequestField (..),
    ResultPayload (..),
    contractSumTypes,
    renderPursContractFooter,
  )
where

import Data.List (intercalate)
import Data.Proxy (Proxy (Proxy))
import Data.Text qualified as Text
import GHC.Generics (Generic)
import Infernix.Models qualified as Models
import Infernix.Types qualified as Types
import Language.PureScript.Bridge (SumType, equal, mkSumType)
import Language.PureScript.Bridge.TypeInfo (Language (Haskell))

data RequestField = RequestField
  { name :: Text.Text,
    label :: Text.Text,
    fieldType :: Text.Text
  }
  deriving (Eq, Generic, Show)

data ModelDescriptor = ModelDescriptor
  { matrixRowId :: Text.Text,
    modelId :: Text.Text,
    displayName :: Text.Text,
    family :: Text.Text,
    description :: Text.Text,
    artifactType :: Text.Text,
    referenceModel :: Text.Text,
    downloadUrl :: Text.Text,
    selectedEngine :: Text.Text,
    runtimeMode :: Text.Text,
    runtimeLane :: Text.Text,
    requiresGpu :: Bool,
    notes :: Text.Text,
    requestShape :: [RequestField]
  }
  deriving (Eq, Generic, Show)

data InferenceRequest = InferenceRequest
  { requestModelId :: Text.Text,
    inputText :: Text.Text
  }
  deriving (Eq, Generic, Show)

data ResultPayload = ResultPayload
  { inlineOutput :: Maybe Text.Text,
    objectRef :: Maybe Text.Text
  }
  deriving (Eq, Generic, Show)

data InferenceResult = InferenceResult
  { requestId :: Text.Text,
    resultModelId :: Text.Text,
    matrixRowId :: Text.Text,
    runtimeMode :: Text.Text,
    selectedEngine :: Text.Text,
    status :: Text.Text,
    payload :: ResultPayload,
    createdAt :: Text.Text
  }
  deriving (Eq, Generic, Show)

data ErrorResponse = ErrorResponse
  { errorCode :: Text.Text,
    message :: Text.Text
  }
  deriving (Eq, Generic, Show)

data EngineBinding = EngineBinding
  { engine :: Text.Text,
    adapterId :: Text.Text,
    adapterType :: Text.Text,
    adapterLocator :: Text.Text,
    adapterEntrypoint :: Text.Text,
    setupEntrypoint :: Text.Text,
    projectDirectory :: Text.Text,
    pythonNative :: Bool
  }
  deriving (Eq, Generic, Show)

contractSumTypes :: [SumType 'Haskell]
contractSumTypes =
  [ let proxy = Proxy :: Proxy RequestField in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ModelDescriptor in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy InferenceRequest in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ResultPayload in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy InferenceResult in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ErrorResponse in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy EngineBinding in equal proxy (mkSumType proxy)
  ]

renderPursContractFooter :: Types.RuntimeMode -> String
renderPursContractFooter activeRuntimeMode =
  let contractEngines = map engineBindingFromInternal (Models.engineBindingsForMode activeRuntimeMode)
      contractModels = map modelDescriptorFromInternal (Models.catalogForMode activeRuntimeMode)
   in "\n"
        <> unlines
          [ "apiBasePath :: String",
            "apiBasePath = " <> show ("/api" :: String),
            "",
            "runtimeMode :: String",
            "runtimeMode = " <> show (Text.unpack (Types.runtimeModeId activeRuntimeMode)),
            "",
            "maxInlineOutputLength :: Int",
            "maxInlineOutputLength = 80",
            "",
            "requestTopics :: Array String",
            "requestTopics = " <> renderPursStringArray (map Text.unpack (Models.requestTopicsForMode activeRuntimeMode)),
            "",
            "resultTopic :: String",
            "resultTopic = " <> show (Text.unpack (Models.resultTopicForMode activeRuntimeMode)),
            "",
            "engines :: Array EngineBinding",
            "engines =",
            "  ["
          ]
        <> intercalate ",\n" (map renderEngineBinding contractEngines)
        <> "\n  ]\n\n"
        <> unlines
          [ "models :: Array ModelDescriptor",
            "models =",
            "  ["
          ]
        <> intercalate ",\n" (map renderModel contractModels)
        <> "\n  ]\n\n"
        <> unlines
          [ "type RequestFieldRecord =",
            "  { name :: String",
            "  , label :: String",
            "  , fieldType :: String",
            "  }",
            "",
            "requestFieldRecord :: RequestField -> RequestFieldRecord",
            "requestFieldRecord (RequestField value) = value",
            "",
            "type ModelDescriptorRecord =",
            "  { matrixRowId :: String",
            "  , modelId :: String",
            "  , displayName :: String",
            "  , family :: String",
            "  , description :: String",
            "  , artifactType :: String",
            "  , referenceModel :: String",
            "  , downloadUrl :: String",
            "  , selectedEngine :: String",
            "  , runtimeMode :: String",
            "  , runtimeLane :: String",
            "  , requiresGpu :: Boolean",
            "  , notes :: String",
            "  , requestShape :: Array RequestFieldRecord",
            "  }",
            "",
            "modelDescriptorRecord :: ModelDescriptor -> ModelDescriptorRecord",
            "modelDescriptorRecord (ModelDescriptor value) =",
            "  { matrixRowId: value.matrixRowId",
            "  , modelId: value.modelId",
            "  , displayName: value.displayName",
            "  , family: value.family",
            "  , description: value.description",
            "  , artifactType: value.artifactType",
            "  , referenceModel: value.referenceModel",
            "  , downloadUrl: value.downloadUrl",
            "  , selectedEngine: value.selectedEngine",
            "  , runtimeMode: value.runtimeMode",
            "  , runtimeLane: value.runtimeLane",
            "  , requiresGpu: value.requiresGpu",
            "  , notes: value.notes",
            "  , requestShape: map requestFieldRecord value.requestShape",
            "  }",
            "",
            "type ResultPayloadRecord =",
            "  { inlineOutput :: Maybe String",
            "  , objectRef :: Maybe String",
            "  }",
            "",
            "resultPayloadRecord :: ResultPayload -> ResultPayloadRecord",
            "resultPayloadRecord (ResultPayload value) = value",
            "",
            "type InferenceResultRecord =",
            "  { requestId :: String",
            "  , resultModelId :: String",
            "  , matrixRowId :: String",
            "  , runtimeMode :: String",
            "  , selectedEngine :: String",
            "  , status :: String",
            "  , payload :: ResultPayloadRecord",
            "  , createdAt :: String",
            "  }",
            "",
            "inferenceResultRecord :: InferenceResult -> InferenceResultRecord",
            "inferenceResultRecord (InferenceResult value) =",
            "  { requestId: value.requestId",
            "  , resultModelId: value.resultModelId",
            "  , matrixRowId: value.matrixRowId",
            "  , runtimeMode: value.runtimeMode",
            "  , selectedEngine: value.selectedEngine",
            "  , status: value.status",
            "  , payload: resultPayloadRecord value.payload",
            "  , createdAt: value.createdAt",
            "  }",
            "",
            "type ErrorResponseRecord =",
            "  { errorCode :: String",
            "  , message :: String",
            "  }",
            "",
            "errorResponseRecord :: ErrorResponse -> ErrorResponseRecord",
            "errorResponseRecord (ErrorResponse value) = value",
            "",
            "type EngineBindingRecord =",
            "  { engine :: String",
            "  , adapterId :: String",
            "  , adapterType :: String",
            "  , adapterLocator :: String",
            "  , adapterEntrypoint :: String",
            "  , setupEntrypoint :: String",
            "  , projectDirectory :: String",
            "  , pythonNative :: Boolean",
            "  }",
            "",
            "engineBindingRecord :: EngineBinding -> EngineBindingRecord",
            "engineBindingRecord (EngineBinding value) = value",
            "",
            "instance readForeignRequestField :: JSON.ReadForeign RequestField where",
            "  readImpl value = RequestField <$> JSON.readImpl value",
            "",
            "instance readForeignModelDescriptor :: JSON.ReadForeign ModelDescriptor where",
            "  readImpl value = ModelDescriptor <$> JSON.readImpl value",
            "",
            "instance readForeignInferenceRequest :: JSON.ReadForeign InferenceRequest where",
            "  readImpl value = InferenceRequest <$> JSON.readImpl value",
            "",
            "instance readForeignResultPayload :: JSON.ReadForeign ResultPayload where",
            "  readImpl value = ResultPayload <$> JSON.readImpl value",
            "",
            "instance readForeignInferenceResult :: JSON.ReadForeign InferenceResult where",
            "  readImpl value = InferenceResult <$> JSON.readImpl value",
            "",
            "instance readForeignErrorResponse :: JSON.ReadForeign ErrorResponse where",
            "  readImpl value = ErrorResponse <$> JSON.readImpl value",
            "",
            "instance readForeignEngineBinding :: JSON.ReadForeign EngineBinding where",
            "  readImpl value = EngineBinding <$> JSON.readImpl value"
          ]

engineBindingFromInternal :: Types.EngineBinding -> EngineBinding
engineBindingFromInternal internalBinding =
  EngineBinding
    { engine = Types.engineBindingName internalBinding,
      adapterId = Types.engineBindingAdapterId internalBinding,
      adapterType = Types.engineBindingAdapterType internalBinding,
      adapterLocator = Types.engineBindingAdapterLocator internalBinding,
      adapterEntrypoint = Types.engineBindingAdapterEntrypoint internalBinding,
      setupEntrypoint = Types.engineBindingSetupEntrypoint internalBinding,
      projectDirectory = Text.pack (Types.engineBindingProjectDirectory internalBinding),
      pythonNative = Types.engineBindingPythonNative internalBinding
    }

modelDescriptorFromInternal :: Types.ModelDescriptor -> ModelDescriptor
modelDescriptorFromInternal internalModel =
  ModelDescriptor
    { matrixRowId = Types.matrixRowId internalModel,
      modelId = Types.modelId internalModel,
      displayName = Types.displayName internalModel,
      family = Types.family internalModel,
      description = Types.description internalModel,
      artifactType = Types.artifactType internalModel,
      referenceModel = Types.referenceModel internalModel,
      downloadUrl = Types.downloadUrl internalModel,
      selectedEngine = Types.selectedEngine internalModel,
      runtimeMode = Types.runtimeModeId (Types.runtimeMode internalModel),
      runtimeLane = Types.runtimeLane internalModel,
      requiresGpu = Types.requiresGpu internalModel,
      notes = Types.notes internalModel,
      requestShape = map requestFieldFromInternal (Types.requestShape internalModel)
    }

requestFieldFromInternal :: Types.RequestField -> RequestField
requestFieldFromInternal internalField =
  RequestField
    { name = Types.name internalField,
      label = Types.label internalField,
      fieldType = Types.fieldType internalField
    }

renderPursStringArray :: [String] -> String
renderPursStringArray values = "[" <> intercalate ", " (map show values) <> "]"

renderEngineBinding :: EngineBinding -> String
renderEngineBinding binding =
  "    EngineBinding\n"
    <> "      { engine: "
    <> show (Text.unpack (engine binding))
    <> "\n"
    <> "      , adapterId: "
    <> show (Text.unpack (adapterId binding))
    <> "\n"
    <> "      , adapterType: "
    <> show (Text.unpack (adapterType binding))
    <> "\n"
    <> "      , adapterLocator: "
    <> show (Text.unpack (adapterLocator binding))
    <> "\n"
    <> "      , adapterEntrypoint: "
    <> show (Text.unpack (adapterEntrypoint binding))
    <> "\n"
    <> "      , setupEntrypoint: "
    <> show (Text.unpack (setupEntrypoint binding))
    <> "\n"
    <> "      , projectDirectory: "
    <> show (Text.unpack (projectDirectory binding))
    <> "\n"
    <> "      , pythonNative: "
    <> (if pythonNative binding then "true" else "false")
    <> "\n"
    <> "      }"

renderModel :: ModelDescriptor -> String
renderModel modelDescriptor =
  let ModelDescriptor
        { matrixRowId = modelMatrixRowId,
          modelId = modelModelId,
          displayName = modelDisplayName,
          family = modelFamily,
          description = modelDescription,
          artifactType = modelArtifactType,
          referenceModel = modelReferenceModel,
          downloadUrl = modelDownloadUrl,
          selectedEngine = modelSelectedEngine,
          runtimeMode = modelRuntimeMode,
          runtimeLane = modelRuntimeLane,
          requiresGpu = modelRequiresGpu,
          notes = modelNotes,
          requestShape = modelRequestShape
        } = modelDescriptor
   in "    ModelDescriptor\n"
        <> "      { matrixRowId: "
        <> show (Text.unpack modelMatrixRowId)
        <> "\n"
        <> "      , modelId: "
        <> show (Text.unpack modelModelId)
        <> "\n"
        <> "      , displayName: "
        <> show (Text.unpack modelDisplayName)
        <> "\n"
        <> "      , family: "
        <> show (Text.unpack modelFamily)
        <> "\n"
        <> "      , description: "
        <> show (Text.unpack modelDescription)
        <> "\n"
        <> "      , artifactType: "
        <> show (Text.unpack modelArtifactType)
        <> "\n"
        <> "      , referenceModel: "
        <> show (Text.unpack modelReferenceModel)
        <> "\n"
        <> "      , downloadUrl: "
        <> show (Text.unpack modelDownloadUrl)
        <> "\n"
        <> "      , selectedEngine: "
        <> show (Text.unpack modelSelectedEngine)
        <> "\n"
        <> "      , runtimeMode: "
        <> show (Text.unpack modelRuntimeMode)
        <> "\n"
        <> "      , runtimeLane: "
        <> show (Text.unpack modelRuntimeLane)
        <> "\n"
        <> "      , requiresGpu: "
        <> (if modelRequiresGpu then "true" else "false")
        <> "\n"
        <> "      , notes: "
        <> show (Text.unpack modelNotes)
        <> "\n"
        <> "      , requestShape:\n"
        <> "          ["
        <> intercalate ", " (map renderRequestField modelRequestShape)
        <> "]\n"
        <> "      }"

renderRequestField :: RequestField -> String
renderRequestField requestField =
  "RequestField { name: "
    <> show (Text.unpack (name requestField))
    <> ", label: "
    <> show (Text.unpack (label requestField))
    <> ", fieldType: "
    <> show (Text.unpack (fieldType requestField))
    <> " }"
