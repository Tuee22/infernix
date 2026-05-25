-- | Phase 7 Sprint 7.10 — durable-context Chat view.
-- |
-- | The supported layout is a left rail of contexts, an active
-- | conversation pane, a draft text box, a cancel button, and a
-- | two-prompt queued indicator. All state changes flow from
-- | server-sent 'ConversationStatePatch' / 'ContextListPatch' /
-- | 'DraftMapPatch' messages applied by trivial mechanical helpers; no
-- | business rule is reimplemented in PureScript.
-- |
-- | This module exposes the projected view state plus the
-- | patch-application helpers the WebSocket handler invokes when a
-- | 'WsServerMessage' arrives. The DOM-level renderer and the SPA
-- | shell-mount remain pending Sprint 7.15 Playwright E2E (which is
-- | what actually exercises this surface end-to-end against a real
-- | cluster).
module Infernix.Web.Chat
  ( ChatViewState
  , initialChatViewState
  , contextListEmpty
  , conversationEmpty
  , applyConversationStatePatch
  , applyContextListPatch
  , applyDraftMapPatch
  , handleServerMessage
  , pendingPromptCount
  ) where

import Prelude

import Data.Array (filter, snoc)
import Data.Foldable (foldl)
import Data.Maybe (Maybe(..))
import Generated.Contracts
  ( ContextId(..)
  , ContextListPatch(..)
  , ContextListState(..)
  , ContextSummary(..)
  , ConversationEvent(..)
  , ConversationInferenceResultPayload(..)
  , ConversationMessage(..)
  , ConversationState(..)
  , ConversationStatePatch(..)
  , DraftEntry(..)
  , DraftMapPatch(..)
  , DraftMapState(..)
  , WsServerMessage(..)
  )

-- | The projected view state the Chat view renders. Contexts come from
-- | the per-user @demo.user.<userId>.contexts@ compacted topic
-- | (via 'ServerContextListSnapshot' / 'ServerContextListPatch');
-- | @activeConversation@ comes from the per-context conversation log
-- | topic (via 'ServerConversationSnapshot' / 'ServerConversationPatch');
-- | @drafts@ come from the per-user drafts compacted topic.
type ChatViewState =
  { contexts :: Array ContextSummary
  , activeConversation :: Maybe ConversationState
  , drafts :: Array DraftEntry
  }

initialChatViewState :: ChatViewState
initialChatViewState =
  { contexts: []
  , activeConversation: Nothing
  , drafts: []
  }

contextListEmpty :: ContextListState -> Boolean
contextListEmpty (ContextListState record) = record.contextListStateContexts == []

conversationEmpty :: ConversationState -> Boolean
conversationEmpty (ConversationState record) =
  record.conversationStateMessages == ([] :: Array ConversationMessage)

-- | Apply a single 'ConversationStatePatch' to the projected state. The
-- | append branch is the hot path (one new message per inference round-
-- | trip); the replace branch is used by the WS handshake after the SPA
-- | reconnects to a new replica and the per-context Pulsar Reader
-- | replays from the cursor.
applyConversationStatePatch
  :: ConversationStatePatch
  -> ConversationState
  -> ConversationState
applyConversationStatePatch patch (ConversationState state) =
  case patch of
    ConversationStateAppendMessage record ->
      ConversationState
        { conversationStateContextId: state.conversationStateContextId
        , conversationStateMessages: snoc state.conversationStateMessages record.appendMessage
        , conversationStatePrefixHash: record.appendNewPrefixHash
        }
    ConversationStateReplaceSnapshot record ->
      record.replaceSnapshot

-- | Apply a single 'ContextListPatch' to the in-memory contexts list.
-- | Upsert keys on 'contextSummaryId'; replace simply takes the supplied
-- | snapshot.
applyContextListPatch
  :: ContextListPatch
  -> Array ContextSummary
  -> Array ContextSummary
applyContextListPatch patch contexts =
  case patch of
    ContextListUpsert record ->
      upsertContext record.contextListUpsertSummary contexts
    ContextListReplaceSnapshot record ->
      case record.contextListReplaceSnapshot of
        ContextListState s -> s.contextListStateContexts

-- | Upsert a 'ContextSummary' by its 'contextSummaryId'. Preserves
-- | existing order when the summary already exists; appends to the end
-- | when it is new.
upsertContext :: ContextSummary -> Array ContextSummary -> Array ContextSummary
upsertContext newSummary existing =
  let
    newId = contextSummaryRawId newSummary
    replaced =
      map
        ( \summary ->
            if contextSummaryRawId summary == newId
              then newSummary
              else summary
        )
        existing
    matched = filter (\summary -> contextSummaryRawId summary == newId) existing
  in
    if matched == []
      then snoc existing newSummary
      else replaced

contextSummaryRawId :: ContextSummary -> String
contextSummaryRawId (ContextSummary record) =
  case record.contextSummaryId of
    ContextId inner -> inner.unContextId

-- | Apply a single 'DraftMapPatch' to the in-memory drafts list. Upsert
-- | and remove key on 'draftEntryContextId'; replace simply takes the
-- | supplied snapshot.
applyDraftMapPatch
  :: DraftMapPatch
  -> Array DraftEntry
  -> Array DraftEntry
applyDraftMapPatch patch existing =
  case patch of
    DraftMapUpsert record ->
      upsertDraft record.draftMapUpsertEntry existing
    DraftMapRemove record ->
      filter
        ( \draft ->
            draftEntryRawId draft /= contextIdRawValue record.draftMapRemoveContextId
        )
        existing
    DraftMapReplaceSnapshot record ->
      case record.draftMapReplaceSnapshot of
        DraftMapState s -> s.draftMapStateDrafts

upsertDraft :: DraftEntry -> Array DraftEntry -> Array DraftEntry
upsertDraft newDraft existing =
  let
    newId = draftEntryRawId newDraft
    replaced =
      map
        ( \draft ->
            if draftEntryRawId draft == newId
              then newDraft
              else draft
        )
        existing
    matched = filter (\draft -> draftEntryRawId draft == newId) existing
  in
    if matched == []
      then snoc existing newDraft
      else replaced

draftEntryRawId :: DraftEntry -> String
draftEntryRawId (DraftEntry record) = contextIdRawValue record.draftEntryContextId

contextIdRawValue :: ContextId -> String
contextIdRawValue (ContextId inner) = inner.unContextId

-- | The supported dispatch helper the WebSocket handler hands off to.
-- | Returns the next view state; the renderer is responsible for
-- | drawing the diff. The @activeContextId@ is the context currently
-- | focused in the left rail — patches targeting a different context
-- | are still applied to the contexts/drafts maps but do not displace
-- | the active conversation pane.
handleServerMessage
  :: Maybe ContextId
  -> WsServerMessage
  -> ChatViewState
  -> ChatViewState
handleServerMessage activeContextId message state =
  case message of
    ServerConversationSnapshot record ->
      state
        { activeConversation = Just record.serverConversationSnapshot
        }
    ServerConversationPatch record ->
      case activeContextId of
        Just active
          | contextIdRawValue active == contextIdRawValue record.serverConversationPatchContextId ->
              state
                { activeConversation =
                    case state.activeConversation of
                      Just current ->
                        Just (applyConversationStatePatch record.serverConversationPatch current)
                      Nothing ->
                        case record.serverConversationPatch of
                          ConversationStateReplaceSnapshot inner -> Just inner.replaceSnapshot
                          _ -> Nothing
                }
        _ -> state
    ServerContextListSnapshot record ->
      case record.serverContextListSnapshot of
        ContextListState inner ->
          state { contexts = inner.contextListStateContexts }
    ServerContextListPatch record ->
      state { contexts = applyContextListPatch record.serverContextListPatch state.contexts }
    ServerDraftMapSnapshot record ->
      case record.serverDraftMapSnapshot of
        DraftMapState inner ->
          state { drafts = inner.draftMapStateDrafts }
    ServerDraftMapPatch record ->
      state { drafts = applyDraftMapPatch record.serverDraftMapPatch state.drafts }
    ServerArtifactReady _ -> state
    ServerInferenceProgress _ -> state
    ServerError _ -> state

-- | Compute how many user prompts in the active conversation do not yet
-- | have a matching 'ConversationInferenceResultEvent'. The UI's
-- | two-prompt queued indicator surfaces when this returns @>= 2@.
pendingPromptCount :: ChatViewState -> Int
pendingPromptCount state =
  case state.activeConversation of
    Nothing -> 0
    Just (ConversationState convo) ->
      foldl step { prompts: 0, results: 0 } convo.conversationStateMessages
        # \r -> r.prompts - r.results
  where
  step acc (ConversationMessage message) =
    case message.conversationMessageEvent of
      ConversationUserPromptEvent _ ->
        acc { prompts = acc.prompts + 1 }
      ConversationInferenceResultEvent (ConversationInferenceResultPayload _) ->
        acc { results = acc.results + 1 }
      _ -> acc
