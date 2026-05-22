{-# LANGUAGE DataKinds #-}
{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE GeneralizedNewtypeDeriving #-}

module Infernix.Web.Contracts
  ( EngineBinding (..),
    ErrorResponse (..),
    InferenceRequest (..),
    InferenceResult (..),
    ModelDescriptor (..),
    RequestField (..),
    ResultPayload (..),
    -- Phase 7 newtypes
    UserId (..),
    ContextId (..),
    MessageId (..),
    ClientIdempotencyKey (..),
    -- Phase 7 object references
    ObjectRef (..),
    ArtifactKind (..),
    ArtifactMimeType (..),
    ArtifactRenderDisposition (..),
    -- Phase 7 event payloads
    UserPromptPayload (..),
    ConversationInferenceResultPayload (..),
    ConversationCancelPayload (..),
    ConversationUserUploadPayload (..),
    -- Phase 7 conversation/state/patch types
    ConversationEvent (..),
    ContextMetadataEvent (..),
    DraftEvent (..),
    ConversationMessage (..),
    ConversationState (..),
    ConversationStatePatch (..),
    ContextSummary (..),
    ContextListState (..),
    ContextListPatch (..),
    DraftEntry (..),
    DraftMapState (..),
    DraftMapPatch (..),
    -- Phase 7 WebSocket envelopes
    WsClientMessage (..),
    WsServerMessage (..),
    -- Phase 7 artifact grants
    ArtifactUploadRequest (..),
    ArtifactUploadGrant (..),
    ArtifactDownloadGrant (..),
    -- helpers
    contractSumTypes,
    renderPursContractFooter,
    taggedSumOptions,
  )
where

import Data.Aeson (FromJSON, ToJSON, defaultOptions)
import Data.Aeson qualified as Aeson
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

-- ----------------------------------------------------------------------------
-- Phase 7: durable-context demo contracts
-- ----------------------------------------------------------------------------

-- | Tagged-sum encoding used by every Phase 7 sum type so the wire format
-- matches PureScript Simple.JSON's tagged-sum-rep convention exactly:
-- @{ "tag": "ConstructorName", "contents": ... }@.
taggedSumOptions :: Aeson.Options
taggedSumOptions =
  defaultOptions {Aeson.sumEncoding = Aeson.TaggedObject "tag" "contents"}

newtype UserId = UserId {unUserId :: Text.Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON)

newtype ContextId = ContextId {unContextId :: Text.Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON)

newtype MessageId = MessageId {unMessageId :: Text.Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON)

newtype ClientIdempotencyKey = ClientIdempotencyKey {unClientIdempotencyKey :: Text.Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON)

data ObjectRef = ObjectRef
  { objectBucket :: Text.Text,
    objectKey :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON ObjectRef

instance FromJSON ObjectRef

data ArtifactKind
  = ArtifactKindUpload
  | ArtifactKindGenerated
  deriving (Eq, Generic, Show)

instance ToJSON ArtifactKind where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON ArtifactKind where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

newtype ArtifactMimeType = ArtifactMimeType {unArtifactMimeType :: Text.Text}
  deriving stock (Generic, Show)
  deriving newtype (Eq, Ord, ToJSON, FromJSON)

data ArtifactRenderDisposition
  = RenderInline
  | DownloadOnly
  | BoundedTextPreview
  | BrowserNativePdf
  deriving (Eq, Generic, Show)

instance ToJSON ArtifactRenderDisposition where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON ArtifactRenderDisposition where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data UserPromptPayload = UserPromptPayload
  { promptText :: Text.Text,
    promptClientIdempotencyKey :: ClientIdempotencyKey,
    promptUserUploads :: [ObjectRef]
  }
  deriving (Eq, Generic, Show)

instance ToJSON UserPromptPayload

instance FromJSON UserPromptPayload

data ConversationInferenceResultPayload = ConversationInferenceResultPayload
  { inferenceResultUserPromptMessageId :: MessageId,
    inferenceResultStatus :: Text.Text,
    inferenceResultInlineOutput :: Maybe Text.Text,
    inferenceResultArtifacts :: [ObjectRef]
  }
  deriving (Eq, Generic, Show)

instance ToJSON ConversationInferenceResultPayload

instance FromJSON ConversationInferenceResultPayload

newtype ConversationCancelPayload = ConversationCancelPayload
  { cancelUserPromptMessageId :: MessageId
  }
  deriving (Eq, Generic, Show)

instance ToJSON ConversationCancelPayload

instance FromJSON ConversationCancelPayload

data ConversationUserUploadPayload = ConversationUserUploadPayload
  { uploadObjectRef :: ObjectRef,
    uploadMimeType :: ArtifactMimeType,
    uploadDisplayName :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON ConversationUserUploadPayload

instance FromJSON ConversationUserUploadPayload

data ConversationEvent
  = ConversationUserPromptEvent UserPromptPayload
  | ConversationInferenceResultEvent ConversationInferenceResultPayload
  | ConversationCancelEvent ConversationCancelPayload
  | ConversationUserUploadEvent ConversationUserUploadPayload
  deriving (Eq, Generic, Show)

instance ToJSON ConversationEvent where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON ConversationEvent where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data ContextMetadataEvent
  = ContextCreated
      { contextCreatedContextId :: ContextId,
        contextCreatedModelId :: Text.Text,
        contextCreatedTitle :: Text.Text
      }
  | ContextRenamed
      { contextRenamedContextId :: ContextId,
        contextRenamedTitle :: Text.Text
      }
  | ContextSoftDeleted
      { contextSoftDeletedContextId :: ContextId
      }
  deriving (Eq, Generic, Show)

instance ToJSON ContextMetadataEvent where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON ContextMetadataEvent where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data DraftEvent
  = DraftUpdated
      { draftUpdatedContextId :: ContextId,
        draftUpdatedText :: Text.Text
      }
  | DraftCleared
      { draftClearedContextId :: ContextId
      }
  deriving (Eq, Generic, Show)

instance ToJSON DraftEvent where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON DraftEvent where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data ConversationMessage = ConversationMessage
  { conversationMessageId :: MessageId,
    conversationMessageEvent :: ConversationEvent
  }
  deriving (Eq, Generic, Show)

instance ToJSON ConversationMessage

instance FromJSON ConversationMessage

data ConversationState = ConversationState
  { conversationStateContextId :: ContextId,
    conversationStateMessages :: [ConversationMessage],
    conversationStatePrefixHash :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON ConversationState

instance FromJSON ConversationState

data ConversationStatePatch
  = ConversationStateAppendMessage
      { appendMessage :: ConversationMessage,
        appendNewPrefixHash :: Text.Text
      }
  | ConversationStateReplaceSnapshot
      { replaceSnapshot :: ConversationState
      }
  deriving (Eq, Generic, Show)

instance ToJSON ConversationStatePatch where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON ConversationStatePatch where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data ContextSummary = ContextSummary
  { contextSummaryId :: ContextId,
    contextSummaryModelId :: Text.Text,
    contextSummaryTitle :: Text.Text,
    contextSummarySoftDeleted :: Bool
  }
  deriving (Eq, Generic, Show)

instance ToJSON ContextSummary

instance FromJSON ContextSummary

newtype ContextListState = ContextListState
  { contextListStateContexts :: [ContextSummary]
  }
  deriving (Eq, Generic, Show)

instance ToJSON ContextListState

instance FromJSON ContextListState

data ContextListPatch
  = ContextListUpsert
      { contextListUpsertSummary :: ContextSummary
      }
  | ContextListReplaceSnapshot
      { contextListReplaceSnapshot :: ContextListState
      }
  deriving (Eq, Generic, Show)

instance ToJSON ContextListPatch where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON ContextListPatch where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data DraftEntry = DraftEntry
  { draftEntryContextId :: ContextId,
    draftEntryText :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON DraftEntry

instance FromJSON DraftEntry

newtype DraftMapState = DraftMapState
  { draftMapStateDrafts :: [DraftEntry]
  }
  deriving (Eq, Generic, Show)

instance ToJSON DraftMapState

instance FromJSON DraftMapState

data DraftMapPatch
  = DraftMapUpsert
      { draftMapUpsertEntry :: DraftEntry
      }
  | DraftMapRemove
      { draftMapRemoveContextId :: ContextId
      }
  | DraftMapReplaceSnapshot
      { draftMapReplaceSnapshot :: DraftMapState
      }
  deriving (Eq, Generic, Show)

instance ToJSON DraftMapPatch where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON DraftMapPatch where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data WsClientMessage
  = ClientHello
      { clientHelloUserId :: UserId
      }
  | ClientSubscribeContext
      { clientSubscribeContextId :: ContextId
      }
  | ClientSubmitPrompt
      { clientSubmitPromptContextId :: ContextId,
        clientSubmitPromptPayload :: UserPromptPayload
      }
  | ClientCancelPrompt
      { clientCancelPromptContextId :: ContextId,
        clientCancelPromptUserPromptMessageId :: MessageId
      }
  | ClientUpdateDraft
      { clientUpdateDraftContextId :: ContextId,
        clientUpdateDraftText :: Text.Text
      }
  | ClientCreateContext
      { clientCreateContextId :: ContextId,
        clientCreateContextModelId :: Text.Text,
        clientCreateContextTitle :: Text.Text
      }
  | ClientRenameContext
      { clientRenameContextId :: ContextId,
        clientRenameContextTitle :: Text.Text
      }
  | ClientSoftDeleteContext
      { clientSoftDeleteContextId :: ContextId
      }
  deriving (Eq, Generic, Show)

instance ToJSON WsClientMessage where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON WsClientMessage where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data WsServerMessage
  = ServerConversationSnapshot
      { serverConversationSnapshot :: ConversationState
      }
  | ServerConversationPatch
      { serverConversationPatchContextId :: ContextId,
        serverConversationPatch :: ConversationStatePatch
      }
  | ServerContextListSnapshot
      { serverContextListSnapshot :: ContextListState
      }
  | ServerContextListPatch
      { serverContextListPatch :: ContextListPatch
      }
  | ServerDraftMapSnapshot
      { serverDraftMapSnapshot :: DraftMapState
      }
  | ServerDraftMapPatch
      { serverDraftMapPatch :: DraftMapPatch
      }
  | ServerArtifactReady
      { serverArtifactReadyContextId :: ContextId,
        serverArtifactReadyObjectRef :: ObjectRef,
        serverArtifactReadyKind :: ArtifactKind
      }
  | ServerInferenceProgress
      { serverInferenceProgressContextId :: ContextId,
        serverInferenceProgressUserPromptMessageId :: MessageId,
        serverInferenceProgressFractionDone :: Double
      }
  | ServerError
      { serverErrorErrorCode :: Text.Text,
        serverErrorMessage :: Text.Text
      }
  deriving (Eq, Generic, Show)

instance ToJSON WsServerMessage where
  toJSON = Aeson.genericToJSON taggedSumOptions

instance FromJSON WsServerMessage where
  parseJSON = Aeson.genericParseJSON taggedSumOptions

data ArtifactUploadRequest = ArtifactUploadRequest
  { artifactUploadRequestContextId :: ContextId,
    artifactUploadRequestMimeType :: ArtifactMimeType,
    artifactUploadRequestDisplayName :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON ArtifactUploadRequest

instance FromJSON ArtifactUploadRequest

data ArtifactUploadGrant = ArtifactUploadGrant
  { artifactUploadGrantObjectRef :: ObjectRef,
    artifactUploadGrantPresignedUrl :: Text.Text,
    artifactUploadGrantExpiresAtIso8601 :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON ArtifactUploadGrant

instance FromJSON ArtifactUploadGrant

data ArtifactDownloadGrant = ArtifactDownloadGrant
  { artifactDownloadGrantObjectRef :: ObjectRef,
    artifactDownloadGrantPresignedUrl :: Text.Text,
    artifactDownloadGrantMimeType :: ArtifactMimeType,
    artifactDownloadGrantRenderDisposition :: ArtifactRenderDisposition,
    artifactDownloadGrantExpiresAtIso8601 :: Text.Text
  }
  deriving (Eq, Generic, Show)

instance ToJSON ArtifactDownloadGrant

instance FromJSON ArtifactDownloadGrant

contractSumTypes :: [SumType 'Haskell]
contractSumTypes =
  [ let proxy = Proxy :: Proxy RequestField in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ModelDescriptor in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy InferenceRequest in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ResultPayload in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy InferenceResult in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ErrorResponse in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy EngineBinding in equal proxy (mkSumType proxy),
    -- Phase 7 newtypes
    let proxy = Proxy :: Proxy UserId in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ContextId in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy MessageId in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ClientIdempotencyKey in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ArtifactMimeType in equal proxy (mkSumType proxy),
    -- Phase 7 object references and artifact descriptors
    let proxy = Proxy :: Proxy ObjectRef in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ArtifactKind in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ArtifactRenderDisposition in equal proxy (mkSumType proxy),
    -- Phase 7 event payload records
    let proxy = Proxy :: Proxy UserPromptPayload in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ConversationInferenceResultPayload in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ConversationCancelPayload in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ConversationUserUploadPayload in equal proxy (mkSumType proxy),
    -- Phase 7 conversation / state / patch types
    let proxy = Proxy :: Proxy ConversationEvent in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ContextMetadataEvent in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy DraftEvent in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ConversationMessage in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ConversationState in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ConversationStatePatch in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ContextSummary in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ContextListState in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ContextListPatch in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy DraftEntry in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy DraftMapState in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy DraftMapPatch in equal proxy (mkSumType proxy),
    -- Phase 7 WebSocket envelopes
    let proxy = Proxy :: Proxy WsClientMessage in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy WsServerMessage in equal proxy (mkSumType proxy),
    -- Phase 7 artifact grants
    let proxy = Proxy :: Proxy ArtifactUploadRequest in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ArtifactUploadGrant in equal proxy (mkSumType proxy),
    let proxy = Proxy :: Proxy ArtifactDownloadGrant in equal proxy (mkSumType proxy)
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
      runtimeLane = Types.runtimeLaneId (Types.runtimeLane internalModel),
      requiresGpu = Types.requiresGpu internalModel,
      notes = Types.notes internalModel,
      requestShape = map requestFieldFromInternal (Types.requestShape internalModel)
    }

requestFieldFromInternal :: Types.RequestField -> RequestField
requestFieldFromInternal internalField =
  RequestField
    { name = Types.name internalField,
      label = Types.label internalField,
      fieldType = Types.requestFieldTypeId (Types.fieldType internalField)
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
