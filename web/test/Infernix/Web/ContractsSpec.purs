-- | Phase 7 Sprint 7.2 — PureScript-side roundtrip coverage for the
-- | durable-context contract surface.
-- |
-- | The Haskell side serialises every Phase 7 sum / record through
-- | Aeson's @TaggedObject "tag" "contents"@ shape. The PureScript side
-- | must decode that exact wire format and re-encode it back to the
-- | same bytes so the WebSocket / @/api/objects@ envelopes stay
-- | symmetric across the language boundary.
module Infernix.Web.ContractsSpec
  ( spec
  ) where

import Prelude

import Data.Either (Either(..))
import Data.Maybe (Maybe(..))
import Data.String (Pattern(..), contains)
import Generated.Contracts
  ( ArtifactKind(..)
  , ArtifactMimeType(..)
  , ArtifactRenderDisposition(..)
  , ClientIdempotencyKey(..)
  , ContextId(..)
  , ContextListPatch(..)
  , ContextMetadataEvent(..)
  , ContextSummary(..)
  , ConversationCancelPayload(..)
  , ConversationEvent(..)
  , ConversationInferenceResultPayload(..)
  , ConversationMessage(..)
  , ConversationState(..)
  , ConversationStatePatch(..)
  , ConversationUserUploadPayload(..)
  , DraftEntry(..)
  , DraftEvent(..)
  , DraftMapPatch(..)
  , DraftMapState(..)
  , MessageId(..)
  , ObjectRef(..)
  , UserId(..)
  , UserPromptPayload(..)
  , WsClientMessage(..)
  , WsServerMessage(..)
  )
import Simple.JSON as JSON
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

-- | A round-tripper: encode through 'JSON.writeJSON', decode back through
-- | 'JSON.readJSON', and assert byte-equality on the re-encoded value. We
-- | re-encode rather than comparing decoded values directly so this
-- | works for sum types that lack 'Eq' on every payload (and stays robust
-- | against any future field-order changes that don't affect the wire).
roundtripJson
  :: forall a
   . JSON.ReadForeign a
  => JSON.WriteForeign a
  => String
  -> a
  -> Spec Unit
roundtripJson label value =
  it ("roundtrips " <> label) do
    let encoded = JSON.writeJSON value
    case (JSON.readJSON encoded :: _ a) of
      Left err ->
        encoded `shouldEqual` ("<decode failed: " <> show err <> ">")
      Right decoded -> do
        let reEncoded = JSON.writeJSON decoded
        reEncoded `shouldEqual` encoded

-- | Assert the encoded wire format contains a specific substring. This
-- | doubles as proof that the @TaggedObject@ shape (tag + spread fields
-- | for records, tag + contents for positional) is what hits the wire.
encodesContaining
  :: forall a
   . JSON.WriteForeign a
  => String
  -> a
  -> String
  -> Spec Unit
encodesContaining label value needle =
  it (label <> " encodes containing " <> needle) do
    let encoded = JSON.writeJSON value
    contains (Pattern needle) encoded `shouldEqual` true

spec :: Spec Unit
spec = do
  describe "Phase 7 contract roundtrips" do
    describe "string newtypes encode as bare strings" do
      encodesContaining "UserId" (UserId { unUserId: "u-1" }) "\"u-1\""
      encodesContaining "ContextId" (ContextId { unContextId: "c-1" }) "\"c-1\""
      encodesContaining "MessageId" (MessageId { unMessageId: "m-1" }) "\"m-1\""
      encodesContaining "ClientIdempotencyKey"
        (ClientIdempotencyKey { unClientIdempotencyKey: "k-1" }) "\"k-1\""
      encodesContaining "ArtifactMimeType"
        (ArtifactMimeType { unArtifactMimeType: "image/png" }) "\"image/png\""
      roundtripJson "UserId" (UserId { unUserId: "u-1" })
      roundtripJson "ContextId" (ContextId { unContextId: "c-1" })
      roundtripJson "MessageId" (MessageId { unMessageId: "m-1" })

    describe "record newtypes encode as their inner record" do
      roundtripJson "ObjectRef"
        (ObjectRef { objectBucket: "infernix-demo-objects", objectKey: "users/u/contexts/c/uploads/x.png" })
      roundtripJson "UserPromptPayload" sampleUserPromptPayload
      roundtripJson "ConversationCancelPayload"
        (ConversationCancelPayload { cancelUserPromptMessageId: MessageId { unMessageId: "m-1" } })

    describe "nullary sums encode as just the tag" do
      encodesContaining "ArtifactKindUpload" ArtifactKindUpload "\"ArtifactKindUpload\""
      encodesContaining "RenderInline" RenderInline "\"RenderInline\""
      roundtripJson "ArtifactKindUpload" ArtifactKindUpload
      roundtripJson "ArtifactKindGenerated" ArtifactKindGenerated
      roundtripJson "RenderInline" RenderInline
      roundtripJson "DownloadOnly" DownloadOnly
      roundtripJson "BoundedTextPreview" BoundedTextPreview
      roundtripJson "BrowserNativePdf" BrowserNativePdf

    describe "positional sums (single arg) encode under 'contents'" do
      encodesContaining "ConversationUserPromptEvent"
        (ConversationUserPromptEvent sampleUserPromptPayload)
        "\"contents\""
      roundtripJson "ConversationUserPromptEvent"
        (ConversationUserPromptEvent sampleUserPromptPayload)
      roundtripJson "ConversationInferenceResultEvent"
        (ConversationInferenceResultEvent sampleInferenceResultPayload)
      roundtripJson "ConversationCancelEvent"
        (ConversationCancelEvent
            (ConversationCancelPayload { cancelUserPromptMessageId: MessageId { unMessageId: "m-2" } }))
      roundtripJson "ConversationUserUploadEvent"
        (ConversationUserUploadEvent sampleUserUploadPayload)

    describe "record-syntax sums spread their fields beside 'tag'" do
      encodesContaining "ContextCreated"
        sampleContextCreated
        "\"contextCreatedContextId\""
      roundtripJson "ContextCreated" sampleContextCreated
      roundtripJson "ContextRenamed"
        (ContextRenamed
            { contextRenamedContextId: ContextId { unContextId: "c-1" }
            , contextRenamedTitle: "Renamed Chat"
            })
      roundtripJson "ContextSoftDeleted"
        (ContextSoftDeleted { contextSoftDeletedContextId: ContextId { unContextId: "c-1" } })
      roundtripJson "DraftUpdated"
        (DraftUpdated
            { draftUpdatedContextId: ContextId { unContextId: "c-1" }
            , draftUpdatedText: "draft text"
            })
      roundtripJson "DraftCleared"
        (DraftCleared { draftClearedContextId: ContextId { unContextId: "c-1" } })

    describe "patch envelopes" do
      roundtripJson "ConversationStateAppendMessage"
        (ConversationStateAppendMessage
            { appendMessage: sampleConversationMessage
            , appendNewPrefixHash: "deadbeef"
            })
      roundtripJson "ConversationStateReplaceSnapshot"
        (ConversationStateReplaceSnapshot { replaceSnapshot: sampleConversationState })
      roundtripJson "ContextListUpsert"
        (ContextListUpsert { contextListUpsertSummary: sampleContextSummary })
      roundtripJson "DraftMapUpsert"
        (DraftMapUpsert { draftMapUpsertEntry: DraftEntry { draftEntryContextId: ContextId { unContextId: "c-1" }, draftEntryText: "x" } })
      roundtripJson "DraftMapRemove"
        (DraftMapRemove { draftMapRemoveContextId: ContextId { unContextId: "c-1" } })
      roundtripJson "DraftMapReplaceSnapshot"
        (DraftMapReplaceSnapshot { draftMapReplaceSnapshot: DraftMapState { draftMapStateDrafts: [] } })

    describe "WebSocket envelopes" do
      roundtripJson "ClientHello"
        (ClientHello { clientHelloUserId: UserId { unUserId: "u-1" } })
      roundtripJson "ClientSubmitPrompt"
        (ClientSubmitPrompt
            { clientSubmitPromptContextId: ContextId { unContextId: "c-1" }
            , clientSubmitPromptPayload: sampleUserPromptPayload
            })
      roundtripJson "ClientRecordUpload"
        (ClientRecordUpload
            { clientRecordUploadContextId: ContextId { unContextId: "c-1" }
            , clientRecordUploadPayload: sampleUserUploadPayload
            })
      roundtripJson "ClientCreateContext"
        (ClientCreateContext
            { clientCreateContextId: ContextId { unContextId: "c-1" }
            , clientCreateContextModelId: "llm-qwen25-safetensors"
            , clientCreateContextTitle: "New Chat"
            })
      roundtripJson "ServerConversationSnapshot"
        (ServerConversationSnapshot { serverConversationSnapshot: sampleConversationState })
      roundtripJson "ServerArtifactReady"
        (ServerArtifactReady
            { serverArtifactReadyContextId: ContextId { unContextId: "c-1" }
            , serverArtifactReadyObjectRef: ObjectRef
                { objectBucket: "infernix-demo-objects"
                , objectKey: "users/u/contexts/c/generated/out.png"
                }
            , serverArtifactReadyKind: ArtifactKindGenerated
            })
      roundtripJson "ServerInferenceProgress"
        (ServerInferenceProgress
            { serverInferenceProgressContextId: ContextId { unContextId: "c-1" }
            , serverInferenceProgressUserPromptMessageId: MessageId { unMessageId: "m-1" }
            , serverInferenceProgressFractionDone: 0.42
            })
      roundtripJson "ServerError"
        (ServerError { serverErrorErrorCode: "unknown-model", serverErrorMessage: "modelId X is not in the active catalog" })

-- Sample fixtures shared across multiple tests.

sampleUserPromptPayload :: UserPromptPayload
sampleUserPromptPayload =
  UserPromptPayload
    { promptText: "hello"
    , promptClientIdempotencyKey: ClientIdempotencyKey { unClientIdempotencyKey: "k-1" }
    , promptUserUploads: []
    }

sampleInferenceResultPayload :: ConversationInferenceResultPayload
sampleInferenceResultPayload =
  ConversationInferenceResultPayload
    { inferenceResultUserPromptMessageId: MessageId { unMessageId: "m-1" }
    , inferenceResultStatus: "completed"
    , inferenceResultInlineOutput: Just "world"
    , inferenceResultArtifacts: []
    }

sampleUserUploadPayload :: ConversationUserUploadPayload
sampleUserUploadPayload =
  ConversationUserUploadPayload
    { uploadObjectRef: ObjectRef
        { objectBucket: "infernix-demo-objects"
        , objectKey: "users/u/contexts/c/uploads/x.png"
        }
    , uploadMimeType: ArtifactMimeType { unArtifactMimeType: "image/png" }
    , uploadDisplayName: "x.png"
    }

sampleConversationMessage :: ConversationMessage
sampleConversationMessage =
  ConversationMessage
    { conversationMessageId: MessageId { unMessageId: "m-1" }
    , conversationMessageEvent: ConversationUserPromptEvent sampleUserPromptPayload
    }

sampleConversationState :: ConversationState
sampleConversationState =
  ConversationState
    { conversationStateContextId: ContextId { unContextId: "c-1" }
    , conversationStateMessages: [ sampleConversationMessage ]
    , conversationStatePrefixHash: "0000"
    }

sampleContextSummary :: ContextSummary
sampleContextSummary =
  ContextSummary
    { contextSummaryId: ContextId { unContextId: "c-1" }
    , contextSummaryModelId: "llm-qwen25-safetensors"
    , contextSummaryTitle: "Sample Context"
    , contextSummarySoftDeleted: false
    }

sampleContextCreated :: ContextMetadataEvent
sampleContextCreated =
  ContextCreated
    { contextCreatedContextId: ContextId { unContextId: "c-1" }
    , contextCreatedModelId: "llm-qwen25-safetensors"
    , contextCreatedTitle: "Sample Context"
    }
