{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE NamedFieldPuns #-}

module Generated.Contracts
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
            "instance writeForeignRequestField :: JSON.WriteForeign RequestField where",
            "  writeImpl (RequestField value) = JSON.writeImpl value",
            "",
            "instance readForeignModelDescriptor :: JSON.ReadForeign ModelDescriptor where",
            "  readImpl value = ModelDescriptor <$> JSON.readImpl value",
            "",
            "instance writeForeignModelDescriptor :: JSON.WriteForeign ModelDescriptor where",
            "  writeImpl (ModelDescriptor value) = JSON.writeImpl value",
            "",
            "instance readForeignInferenceRequest :: JSON.ReadForeign InferenceRequest where",
            "  readImpl value = InferenceRequest <$> JSON.readImpl value",
            "",
            "instance writeForeignInferenceRequest :: JSON.WriteForeign InferenceRequest where",
            "  writeImpl (InferenceRequest value) = JSON.writeImpl value",
            "",
            "instance readForeignResultPayload :: JSON.ReadForeign ResultPayload where",
            "  readImpl value = ResultPayload <$> JSON.readImpl value",
            "",
            "instance writeForeignResultPayload :: JSON.WriteForeign ResultPayload where",
            "  writeImpl (ResultPayload value) = JSON.writeImpl value",
            "",
            "instance readForeignInferenceResult :: JSON.ReadForeign InferenceResult where",
            "  readImpl value = InferenceResult <$> JSON.readImpl value",
            "",
            "instance writeForeignInferenceResult :: JSON.WriteForeign InferenceResult where",
            "  writeImpl (InferenceResult value) = JSON.writeImpl value",
            "",
            "instance readForeignErrorResponse :: JSON.ReadForeign ErrorResponse where",
            "  readImpl value = ErrorResponse <$> JSON.readImpl value",
            "",
            "instance writeForeignErrorResponse :: JSON.WriteForeign ErrorResponse where",
            "  writeImpl (ErrorResponse value) = JSON.writeImpl value",
            "",
            "instance readForeignEngineBinding :: JSON.ReadForeign EngineBinding where",
            "  readImpl value = EngineBinding <$> JSON.readImpl value",
            "",
            "instance writeForeignEngineBinding :: JSON.WriteForeign EngineBinding where",
            "  writeImpl (EngineBinding value) = JSON.writeImpl value"
          ]

requestFieldFromInternal :: Types.RequestField -> RequestField
requestFieldFromInternal fieldValue =
  RequestField
    { name = Types.name fieldValue,
      label = Types.label fieldValue,
      fieldType = Types.fieldType fieldValue
    }

modelDescriptorFromInternal :: Types.ModelDescriptor -> ModelDescriptor
modelDescriptorFromInternal modelValue =
  ModelDescriptor
    { matrixRowId = Types.matrixRowId modelValue,
      modelId = Types.modelId modelValue,
      displayName = Types.displayName modelValue,
      family = Types.family modelValue,
      description = Types.description modelValue,
      artifactType = Types.artifactType modelValue,
      referenceModel = Types.referenceModel modelValue,
      downloadUrl = Types.downloadUrl modelValue,
      selectedEngine = Types.selectedEngine modelValue,
      runtimeMode = Types.runtimeModeId (Types.runtimeMode modelValue),
      runtimeLane = Types.runtimeLane modelValue,
      requiresGpu = Types.requiresGpu modelValue,
      notes = Types.notes modelValue,
      requestShape = map requestFieldFromInternal (Types.requestShape modelValue)
    }

engineBindingFromInternal :: Types.EngineBinding -> EngineBinding
engineBindingFromInternal bindingValue =
  EngineBinding
    { engine = Types.engineBindingName bindingValue,
      adapterId = Types.engineBindingAdapterId bindingValue,
      adapterType = Types.engineBindingAdapterType bindingValue,
      adapterLocator = Types.engineBindingAdapterLocator bindingValue,
      adapterEntrypoint = Types.engineBindingAdapterEntrypoint bindingValue,
      setupEntrypoint = Types.engineBindingSetupEntrypoint bindingValue,
      projectDirectory = Text.pack (Types.engineBindingProjectDirectory bindingValue),
      pythonNative = Types.engineBindingPythonNative bindingValue
    }

renderEngineBinding :: EngineBinding -> String
renderEngineBinding bindingValue =
  unlines
    [ "    EngineBinding",
      "      { engine: " <> showText (engine bindingValue),
      "      , adapterId: " <> showText (adapterId bindingValue),
      "      , adapterType: " <> showText (adapterType bindingValue),
      "      , adapterLocator: " <> showText (adapterLocator bindingValue),
      "      , adapterEntrypoint: " <> showText (adapterEntrypoint bindingValue),
      "      , setupEntrypoint: " <> showText (setupEntrypoint bindingValue),
      "      , projectDirectory: " <> showText (projectDirectory bindingValue),
      "      , pythonNative: " <> psBool (pythonNative bindingValue),
      "      }"
    ]

renderModel :: ModelDescriptor -> String
renderModel ModelDescriptor {matrixRowId, modelId, displayName, family, description, artifactType, referenceModel, downloadUrl, selectedEngine, runtimeMode, runtimeLane, requiresGpu, notes, requestShape} =
  unlines
    [ "    ModelDescriptor",
      "      { matrixRowId: " <> showText matrixRowId,
      "      , modelId: " <> showText modelId,
      "      , displayName: " <> showText displayName,
      "      , family: " <> showText family,
      "      , description: " <> showText description,
      "      , artifactType: " <> showText artifactType,
      "      , referenceModel: " <> showText referenceModel,
      "      , downloadUrl: " <> showText downloadUrl,
      "      , selectedEngine: " <> showText selectedEngine,
      "      , runtimeMode: " <> showText runtimeMode,
      "      , runtimeLane: " <> showText runtimeLane,
      "      , requiresGpu: " <> psBool requiresGpu,
      "      , notes: " <> showText notes,
      "      , requestShape: " <> renderRequestShape requestShape,
      "      }"
    ]

renderRequestShape :: [RequestField] -> String
renderRequestShape fields =
  "[ " <> intercalate ", " (map renderRequestField fields) <> " ]"

renderRequestField :: RequestField -> String
renderRequestField fieldValue =
  "RequestField { name: "
    <> showText (name fieldValue)
    <> ", label: "
    <> showText (label fieldValue)
    <> ", fieldType: "
    <> showText (fieldType fieldValue)
    <> " }"

renderPursStringArray :: [String] -> String
renderPursStringArray values =
  "[ " <> intercalate ", " (map show values) <> " ]"

psBool :: Bool -> String
psBool True = "true"
psBool False = "false"

showText :: Text.Text -> String
showText = show . Text.unpack
