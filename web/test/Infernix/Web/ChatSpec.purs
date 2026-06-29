-- | Phase 7 Sprint 7.13 — view-model tests for the durable-context Chat
-- | view. The browser only applies patches; no business rule is
-- | reimplemented in PureScript, so this spec exercises exactly that
-- | mechanical surface plus the projected-state helpers the renderer
-- | will read.
module Infernix.Web.ChatSpec
  ( spec
  ) where

import Prelude

import Data.Array (length, (!!))
import Data.Maybe (Maybe(..))
import Generated.Contracts
  ( ClientIdempotencyKey(..)
  , ContextId(..)
  , ContextListPatch(..)
  , ContextSummary(..)
  , ConversationCancelPayload(..)
  , ConversationEvent(..)
  , ConversationInferenceResultPayload(..)
  , ConversationMessage(..)
  , ConversationState(..)
  , ConversationStatePatch(..)
  , DraftEntry(..)
  , DraftMapPatch(..)
  , MessageId(..)
  , ObjectRef
  , UserPromptPayload(..)
  , WsServerMessage(..)
  )
import Infernix.Web.Chat
  ( applyContextListPatch
  , applyConversationStatePatch
  , applyDraftMapPatch
  , handleServerMessage
  , initialChatViewState
  , latestPendingPromptMessageId
  , pendingPromptCount
  )
import Test.Spec (Spec, describe, it)
import Test.Spec.Assertions (shouldEqual)

spec :: Spec Unit
spec = do
  describe "ChatView patch helpers" do
    describe "ConversationStatePatch" do
      it "appends a message and updates the prefix hash" do
        let original = sampleConversation [ promptMessage "m-1" "hello" ]
        let patched =
              applyConversationStatePatch
                ( ConversationStateAppendMessage
                    { appendMessage: resultMessage "m-1"
                    , appendNewPrefixHash: "abc123"
                    }
                )
                original
        conversationMessageCount patched `shouldEqual` 2
        conversationPrefixHash patched `shouldEqual` "abc123"

      it "replaces the snapshot wholesale" do
        let snapshot = sampleConversation [ promptMessage "m-7" "fresh" ]
        let patched =
              applyConversationStatePatch
                (ConversationStateReplaceSnapshot { replaceSnapshot: snapshot })
                (sampleConversation [])
        conversationMessageCount patched `shouldEqual` 1
        conversationPrefixHash patched `shouldEqual` "0000"

    describe "ContextListPatch" do
      it "upserts a new context summary at the end" do
        let s1 = sampleContextSummary "c-1" "Chat 1"
        let s2 = sampleContextSummary "c-2" "Chat 2"
        let result = applyContextListPatch (ContextListUpsert { contextListUpsertSummary: s2 }) [ s1 ]
        length result `shouldEqual` 2

      it "upserts an existing context in place" do
        let s1 = sampleContextSummary "c-1" "Chat 1"
        let s1Renamed = sampleContextSummary "c-1" "Chat 1 Renamed"
        let result = applyContextListPatch (ContextListUpsert { contextListUpsertSummary: s1Renamed }) [ s1 ]
        length result `shouldEqual` 1
        contextSummaryTitleAt 0 result `shouldEqual` "Chat 1 Renamed"

    describe "DraftMapPatch" do
      it "upserts a draft" do
        let d1 = sampleDraft "c-1" "draft text"
        let result = applyDraftMapPatch (DraftMapUpsert { draftMapUpsertEntry: d1 }) []
        length result `shouldEqual` 1

      it "removes a draft by contextId" do
        let d1 = sampleDraft "c-1" "draft text"
        let result =
              applyDraftMapPatch
                (DraftMapRemove { draftMapRemoveContextId: ContextId { unContextId: "c-1" } })
                [ d1 ]
        length result `shouldEqual` 0

  describe "ChatView handleServerMessage" do
    it "sets activeConversation from a snapshot" do
      let snapshot = sampleConversation [ promptMessage "m-1" "hi" ]
      let next =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      case next.activeConversation of
        Just _ -> pure unit
        Nothing -> "<activeConversation should not be Nothing>" `shouldEqual` "<set>"

    it "appends a message to the active conversation only when contextIds match" do
      let snapshot = sampleConversation [ promptMessage "m-1" "hi" ]
      let stateWithActive =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      let nextMatching =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              ( ServerConversationPatch
                  { serverConversationPatchContextId: ContextId { unContextId: "c-1" }
                  , serverConversationPatch:
                      ConversationStateAppendMessage
                        { appendMessage: resultMessage "m-1"
                        , appendNewPrefixHash: "deadbeef"
                        }
                  }
              )
              stateWithActive
      case nextMatching.activeConversation of
        Just conv -> conversationMessageCount conv `shouldEqual` 2
        Nothing -> "<should still have activeConversation>" `shouldEqual` "<set>"

      let nextDifferent =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              ( ServerConversationPatch
                  { serverConversationPatchContextId: ContextId { unContextId: "c-9" }
                  , serverConversationPatch:
                      ConversationStateAppendMessage
                        { appendMessage: resultMessage "m-9"
                        , appendNewPrefixHash: "ffff"
                        }
                  }
              )
              stateWithActive
      case nextDifferent.activeConversation of
        Just conv -> conversationMessageCount conv `shouldEqual` 1
        Nothing -> "<should still have activeConversation>" `shouldEqual` "<set>"

    it "replaces an optimistic prompt when the broker patch carries the same idempotency key" do
      let snapshot = sampleConversation [ promptMessage "prompt-local" "hi" ]
      let patched =
            applyConversationStatePatch
              ( ConversationStateAppendMessage
                  { appendMessage: promptMessageWithKey "ledger-1:0" "prompt-local" "hi"
                  , appendNewPrefixHash: "canonical"
                  }
              )
              snapshot
      conversationMessageCount patched `shouldEqual` 1
      conversationMessageIdAt 0 patched `shouldEqual` "ledger-1:0"
      conversationPrefixHash patched `shouldEqual` "canonical"

  describe "ChatView pendingPromptCount" do
    it "is zero when the conversation is empty" do
      pendingPromptCount initialChatViewState `shouldEqual` 0

    it "counts one queued prompt when a single prompt has no result" do
      let snapshot = sampleConversation [ promptMessage "m-1" "hi" ]
      let state =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      pendingPromptCount state `shouldEqual` 1

    it "counts two queued prompts when a second is submitted before the first resolves" do
      let snapshot =
            sampleConversation
              [ promptMessage "m-1" "first", promptMessage "m-2" "second" ]
      let state =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      pendingPromptCount state `shouldEqual` 2

    it "returns to zero after both prompts produce inference results" do
      let snapshot =
            sampleConversation
              [ promptMessage "m-1" "first"
              , resultMessage "m-1"
              , promptMessage "m-2" "second"
              , resultMessage "m-2"
              ]
      let state =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      pendingPromptCount state `shouldEqual` 0

    it "treats a cancel event as resolving its target prompt" do
      let snapshot =
            sampleConversation
              [ promptMessage "m-1" "first"
              , cancelMessage "m-1"
              ]
      let state =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      pendingPromptCount state `shouldEqual` 0

    it "returns the latest unresolved prompt id for the cancel action" do
      let snapshot =
            sampleConversation
              [ promptMessage "m-1" "first"
              , cancelMessage "m-1"
              , promptMessage "m-2" "second"
              ]
      let state =
            handleServerMessage
              (Just (ContextId { unContextId: "c-1" }))
              (ServerConversationSnapshot { serverConversationSnapshot: snapshot })
              initialChatViewState
      messageIdMaybeText (latestPendingPromptMessageId state) `shouldEqual` Just "m-2"

-- Sample fixtures.

sampleConversation :: Array ConversationMessage -> ConversationState
sampleConversation messages =
  ConversationState
    { conversationStateContextId: ContextId { unContextId: "c-1" }
    , conversationStateMessages: messages
    , conversationStatePrefixHash: "0000"
    }

promptMessage :: String -> String -> ConversationMessage
promptMessage messageId text =
  promptMessageWithKey messageId messageId text

promptMessageWithKey :: String -> String -> String -> ConversationMessage
promptMessageWithKey messageId idempotencyKey text =
  ConversationMessage
    { conversationMessageId: MessageId { unMessageId: messageId }
    , conversationMessageEvent: ConversationUserPromptEvent
        ( UserPromptPayload
            { promptText: text
            , promptClientIdempotencyKey: ClientIdempotencyKey { unClientIdempotencyKey: idempotencyKey }
            , promptUserUploads: ([] :: Array ObjectRef)
            }
        )
    }

resultMessage :: String -> ConversationMessage
resultMessage promptMessageId =
  ConversationMessage
    { conversationMessageId: MessageId { unMessageId: promptMessageId <> "-result" }
    , conversationMessageEvent: ConversationInferenceResultEvent
        ( ConversationInferenceResultPayload
            { inferenceResultUserPromptMessageId: MessageId { unMessageId: promptMessageId }
            , inferenceResultStatus: "completed"
            , inferenceResultInlineOutput: Just "result text"
            , inferenceResultArtifacts: []
            }
        )
    }

cancelMessage :: String -> ConversationMessage
cancelMessage promptMessageId =
  ConversationMessage
    { conversationMessageId: MessageId { unMessageId: promptMessageId <> "-cancel" }
    , conversationMessageEvent: ConversationCancelEvent
        (ConversationCancelPayload { cancelUserPromptMessageId: MessageId { unMessageId: promptMessageId } })
    }

sampleContextSummary :: String -> String -> ContextSummary
sampleContextSummary contextIdRaw title =
  ContextSummary
    { contextSummaryId: ContextId { unContextId: contextIdRaw }
    , contextSummaryModelId: "llm-smollm2-safetensors"
    , contextSummaryTitle: title
    , contextSummarySoftDeleted: false
    }

sampleDraft :: String -> String -> DraftEntry
sampleDraft contextIdRaw text =
  DraftEntry
    { draftEntryContextId: ContextId { unContextId: contextIdRaw }
    , draftEntryText: text
    }

conversationMessageCount :: ConversationState -> Int
conversationMessageCount (ConversationState record) = length record.conversationStateMessages

conversationPrefixHash :: ConversationState -> String
conversationPrefixHash (ConversationState record) = record.conversationStatePrefixHash

conversationMessageIdAt :: Int -> ConversationState -> String
conversationMessageIdAt idx (ConversationState record) =
  case record.conversationStateMessages !! idx of
    Just (ConversationMessage message) ->
      case message.conversationMessageId of
        MessageId messageId -> messageId.unMessageId
    Nothing -> "<missing>"

messageIdMaybeText :: Maybe MessageId -> Maybe String
messageIdMaybeText maybeMessageId =
  case maybeMessageId of
    Just (MessageId messageId) -> Just messageId.unMessageId
    Nothing -> Nothing

contextSummaryTitleAt :: Int -> Array ContextSummary -> String
contextSummaryTitleAt idx contexts =
  case contexts !! idx of
    Just (ContextSummary record) -> record.contextSummaryTitle
    Nothing -> "<missing>"
