-- | Phase 7 Sprint 7.10 — durable-context Chat view.
-- |
-- | The supported layout is a left rail of contexts, an active
-- | conversation pane, a draft text box, a cancel button, and a
-- | two-prompt queued indicator. All state changes flow from
-- | server-sent 'ConversationStatePatch' / 'ContextListPatch' /
-- | 'DraftMapPatch' messages applied by trivial mechanical helpers; no
-- | business rule is reimplemented in PureScript.
-- |
-- | This module exposes the projected view state, patch-application
-- | helpers, and DOM renderer the durable-context shell mounts. The
-- | shell swap itself remains Sprint 7.15 Playwright E2E work because
-- | that is what exercises the routed Keycloak + WebSocket path against
-- | a real cluster.
module Infernix.Web.Chat
  ( ChatViewState
  , ChatRenderOptions
  , initialChatViewState
  , contextListEmpty
  , conversationEmpty
  , conversationForContext
  , projectRenderableChatState
  , applyConversationStatePatch
  , upsertConversationState
  , applyContextListPatch
  , applyDraftMapPatch
  , handleServerMessage
  , latestPendingPromptMessageId
  , messageSummary
  , pendingPromptCount
  , renderChatView
  ) where

import Prelude

import Data.Array (filter, find, last, length, snoc)
import Data.Foldable (foldl, traverse_)
import Data.Maybe (Maybe(..), fromMaybe, isJust)
import Data.String (Pattern(..), stripSuffix)
import Effect (Effect)
import Generated.Contracts
  ( ClientIdempotencyKey(..)
  , ContextId(..)
  , ContextListPatch(..)
  , ContextListState(..)
  , ContextSummary(..)
  , ArtifactMimeType(..)
  , ConversationCancelPayload(..)
  , ConversationEvent(..)
  , ConversationInferenceResultPayload(..)
  , ConversationMessage(..)
  , ConversationState(..)
  , ConversationStatePatch(..)
  , ConversationUserUploadPayload(..)
  , DraftEntry(..)
  , DraftMapPatch(..)
  , DraftMapState(..)
  , InferenceError(..)
  , MessageId(..)
  , ModelDescriptor
  , ObjectRef(..)
  , UserPromptPayload(..)
  , WsServerMessage(..)
  , modelDescriptorRecord
  )
import Web.DOM.Document as Document
import Web.DOM.Element as Element
import Web.DOM.Node as Node

-- | Additional state the shell owns and hands to the renderer. The
-- | renderer does not bind events; it emits stable data attributes for
-- | the shell's event layer.
type ChatRenderOptions =
  { activeContextId :: Maybe ContextId
  , selectedModelId :: Maybe String
  , models :: Array ModelDescriptor
  , newContextDialogOpen :: Boolean
  }

-- | The projected view state the Chat view renders. Contexts come from
-- | the per-user @demo.user.<userId>.contexts@ compacted topic
-- | (via 'ServerContextListSnapshot' / 'ServerContextListPatch');
-- | @activeConversation@ comes from the per-context conversation log
-- | topic (via 'ServerConversationSnapshot' / 'ServerConversationPatch');
-- | @drafts@ come from the per-user drafts compacted topic.
type ChatViewState =
  { contexts :: Array ContextSummary
  , activeConversation :: Maybe ConversationState
  , conversations :: Array ConversationState
  , drafts :: Array DraftEntry
  }

initialChatViewState :: ChatViewState
initialChatViewState =
  { contexts: []
  , activeConversation: Nothing
  , conversations: []
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
        , conversationStateMessages: upsertConversationMessage record.appendMessage state.conversationStateMessages
        , conversationStatePrefixHash: record.appendNewPrefixHash
        }
    ConversationStateReplaceSnapshot record ->
      record.replaceSnapshot

upsertConversationMessage
  :: ConversationMessage
  -> Array ConversationMessage
  -> Array ConversationMessage
upsertConversationMessage newMessage existing =
  let
    newId = conversationMessageRawId newMessage
    idMatched = filter (\message -> conversationMessageRawId message == newId) existing
    idReplaced =
      map
        ( \message ->
            if conversationMessageRawId message == newId then
              newMessage
            else
              message
        )
        existing
  in
    if idMatched /= [] then
      idReplaced
    else
      case promptKeyText newMessage of
        Just newPromptKey ->
          let
            promptMatched =
              filter (\message -> promptKeyText message == Just newPromptKey) existing
            promptReplaced =
              map
                ( \message ->
                    if promptKeyText message == Just newPromptKey then
                      newMessage
                    else
                      message
                )
                existing
          in
            if promptMatched == [] then
              snoc existing newMessage
            else
              promptReplaced
        Nothing ->
          snoc existing newMessage

conversationMessageRawId :: ConversationMessage -> String
conversationMessageRawId (ConversationMessage record) =
  messageIdRawValue record.conversationMessageId

conversationStateContextIdRaw :: ConversationState -> String
conversationStateContextIdRaw (ConversationState record) =
  contextIdRawValue record.conversationStateContextId

conversationForContext :: ContextId -> ChatViewState -> Maybe ConversationState
conversationForContext contextId state =
  find (conversationTargetsContext contextId) state.conversations

conversationForPatchContext :: ContextId -> ChatViewState -> Maybe ConversationState
conversationForPatchContext contextId state =
  case conversationForContext contextId state of
    Just conversation -> Just conversation
    Nothing ->
      case state.activeConversation of
        Just conversation | conversationTargetsContext contextId conversation -> Just conversation
        _ -> Nothing

upsertConversationState :: ConversationState -> Array ConversationState -> Array ConversationState
upsertConversationState newConversation existing =
  let
    newId = conversationStateContextIdRaw newConversation
    matched =
      filter (\conversation -> conversationStateContextIdRaw conversation == newId) existing
    replaced =
      map
        ( \conversation ->
            if conversationStateContextIdRaw conversation == newId then
              newConversation
            else
              conversation
        )
        existing
  in
    if matched == [] then
      snoc existing newConversation
    else
      replaced

promptKeyText :: ConversationMessage -> Maybe String
promptKeyText (ConversationMessage record) =
  case record.conversationMessageEvent of
    ConversationUserPromptEvent (UserPromptPayload prompt) ->
      case prompt.promptClientIdempotencyKey of
        ClientIdempotencyKey key -> Just key.unClientIdempotencyKey
    _ -> Nothing

mergeConversationSnapshot
  :: ConversationState
  -> Maybe ConversationState
  -> ConversationState
mergeConversationSnapshot incoming current =
  case current of
    Just (ConversationState currentRecord) ->
      case incoming of
        ConversationState incomingRecord ->
          if contextIdRawValue currentRecord.conversationStateContextId == contextIdRawValue incomingRecord.conversationStateContextId then
            let
              retained =
                filter
                  (\message -> not (messageRepresentedIn incomingRecord.conversationStateMessages message))
                  currentRecord.conversationStateMessages
            in
              if retained == [] then
                incoming
              else
                ConversationState
                  { conversationStateContextId: incomingRecord.conversationStateContextId
                  , conversationStateMessages: incomingRecord.conversationStateMessages <> retained
                  , conversationStatePrefixHash: currentRecord.conversationStatePrefixHash
                  }
          else
            incoming
    _ -> incoming

messageRepresentedIn :: Array ConversationMessage -> ConversationMessage -> Boolean
messageRepresentedIn messages candidate =
  isJust (find (conversationMessageRepresents candidate) messages)

conversationMessageRepresents :: ConversationMessage -> ConversationMessage -> Boolean
conversationMessageRepresents candidate message =
  conversationMessageRawId message == conversationMessageRawId candidate
    || case promptKeyText candidate of
        Just key -> promptKeyText message == Just key
        Nothing -> false

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

snapshotTargetsActiveContext :: Maybe ContextId -> ConversationState -> Boolean
snapshotTargetsActiveContext activeContextId (ConversationState record) =
  case activeContextId of
    Just active ->
      contextIdRawValue active == contextIdRawValue record.conversationStateContextId
    Nothing -> false

snapshotTargetsRenderedConversation :: Maybe ConversationState -> ConversationState -> Boolean
snapshotTargetsRenderedConversation current incoming =
  case current of
    Just (ConversationState currentRecord) ->
      case incoming of
        ConversationState incomingRecord ->
          contextIdRawValue currentRecord.conversationStateContextId == contextIdRawValue incomingRecord.conversationStateContextId
    Nothing -> false

conversationTargetsContext :: ContextId -> ConversationState -> Boolean
conversationTargetsContext contextId (ConversationState record) =
  contextIdRawValue contextId == contextIdRawValue record.conversationStateContextId

patchTargetsActiveContext :: Maybe ContextId -> ContextId -> Boolean
patchTargetsActiveContext activeContextId patchContextId =
  case activeContextId of
    Just active ->
      contextIdRawValue active == contextIdRawValue patchContextId
    Nothing -> false

patchTargetsRenderedConversation :: Maybe ConversationState -> ContextId -> Boolean
patchTargetsRenderedConversation current patchContextId =
  case current of
    Just conversation -> conversationTargetsContext patchContextId conversation
    Nothing -> false

conversationFromActivePatch :: ContextId -> ConversationStatePatch -> ConversationState
conversationFromActivePatch active patch =
  case patch of
    ConversationStateReplaceSnapshot inner -> inner.replaceSnapshot
    ConversationStateAppendMessage inner ->
      ConversationState
        { conversationStateContextId: active
        , conversationStateMessages: [ inner.appendMessage ]
        , conversationStatePrefixHash: inner.appendNewPrefixHash
        }

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
      let
        snapshot = record.serverConversationSnapshot
        snapshotContext =
          case snapshot of
            ConversationState snapshotRecord -> snapshotRecord.conversationStateContextId
        existing =
          case conversationForContext snapshotContext state of
            Just stored -> Just stored
            Nothing -> state.activeConversation
        merged = mergeConversationSnapshot snapshot existing
        conversations = upsertConversationState merged state.conversations
        shouldRender =
          snapshotTargetsActiveContext activeContextId snapshot
            || snapshotTargetsRenderedConversation state.activeConversation snapshot
      in
        if shouldRender then
          state
            { activeConversation = Just merged
            , conversations = conversations
            }
        else
          state { conversations = conversations }
    ServerConversationPatch record ->
      let
        patchContext = record.serverConversationPatchContextId
        patched =
          case conversationForPatchContext patchContext state of
            Just current ->
              applyConversationStatePatch record.serverConversationPatch current
            Nothing ->
              conversationFromActivePatch patchContext record.serverConversationPatch
        conversations = upsertConversationState patched state.conversations
        shouldRender =
          patchTargetsActiveContext activeContextId patchContext
            || patchTargetsRenderedConversation state.activeConversation patchContext
      in
        if shouldRender then
          state
            { activeConversation = Just patched
            , conversations = conversations
            }
        else
          state { conversations = conversations }
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
-- | have a matching result or cancel event. The UI's
-- | two-prompt queued indicator surfaces when this returns @>= 2@.
pendingPromptCount :: ChatViewState -> Int
pendingPromptCount state = length (pendingPromptMessageIds state)

latestPendingPromptMessageId :: ChatViewState -> Maybe MessageId
latestPendingPromptMessageId state =
  last (pendingPromptMessageIds state)

pendingPromptMessageIds :: ChatViewState -> Array MessageId
pendingPromptMessageIds state =
  case state.activeConversation of
    Nothing -> []
    Just (ConversationState convo) ->
      foldl (collectPendingPrompt convo.conversationStateMessages) [] convo.conversationStateMessages
  where
  collectPendingPrompt messages pending message =
    case promptMessageId message of
      Nothing -> pending
      Just messageId ->
        if promptResolvedBy messages messageId then
          pending
        else
          snoc pending messageId

promptMessageId :: ConversationMessage -> Maybe MessageId
promptMessageId (ConversationMessage message) =
  case message.conversationMessageEvent of
    ConversationUserPromptEvent _ ->
      Just message.conversationMessageId
    _ -> Nothing

promptResolvedBy :: Array ConversationMessage -> MessageId -> Boolean
promptResolvedBy messages messageId =
  case find (messageResolvesPrompt messageId) messages of
    Just _ -> true
    Nothing -> false

messageResolvesPrompt :: MessageId -> ConversationMessage -> Boolean
messageResolvesPrompt messageId (ConversationMessage message) =
  case message.conversationMessageEvent of
    ConversationInferenceResultEvent (ConversationInferenceResultPayload result) ->
      result.inferenceResultUserPromptMessageId == messageId
    ConversationCancelEvent (ConversationCancelPayload cancel) ->
      cancel.cancelUserPromptMessageId == messageId
    _ -> false

-- | Render the durable-context Chat surface into an existing container.
-- | The structure is deliberately plain: a context rail, a model picker,
-- | conversation stream, draft editor, cancel action, and pending-prompt
-- | indicator. Business logic remains in Haskell; this only projects
-- | already-received state.
renderChatView
  :: Document.Document
  -> Element.Element
  -> ChatRenderOptions
  -> ChatViewState
  -> Effect Unit
renderChatView document container options state = do
  let renderState = projectRenderableChatState options.activeContextId state
  clearChildren container
  shell <- createElement document "div" "chat-view"
  contextRail <- renderContextRail document options renderState
  conversationPane <- renderConversationPane document options renderState
  appendElement shell contextRail
  appendElement shell conversationPane
  appendElement container shell

-- | The reducer keeps a per-context conversation cache and a last-rendered
-- | conversation. When fast patches land while shell focus is changing, the
-- | cache can be newer than @activeConversation@. Rendering keys on the shell's
-- | active context first so a stored terminal result cannot be hidden behind a
-- | stale pane.
projectRenderableChatState :: Maybe ContextId -> ChatViewState -> ChatViewState
projectRenderableChatState activeContextId state =
  case activeContextId >>= \contextId -> conversationForContext contextId state of
    Just conversation -> state { activeConversation = Just conversation }
    Nothing -> state

renderContextRail
  :: Document.Document
  -> ChatRenderOptions
  -> ChatViewState
  -> Effect Element.Element
renderContextRail document options state = do
  rail <- createElement document "aside" "chat-context-rail"
  header <- textElement document "h2" "chat-section-title" "Contexts"
  appendElement rail header
  openNewContext <- textElement document "button" "chat-new-context-button" "New context"
  Element.setAttribute "type" "button" openNewContext
  Element.setAttribute "data-role" "open-new-context" openNewContext
  appendElement rail openNewContext
  when options.newContextDialogOpen do
    newContextDialog <- renderNewContextDialog document options
    appendElement rail newContextDialog
  list <- createElement document "div" "chat-context-list"
  if state.contexts == [] then do
    empty <- textElement document "p" "chat-empty-state" "No contexts yet."
    appendElement list empty
  else
    traverse_ (appendContextButton document options list) state.contexts
  appendElement rail list
  pure rail

renderNewContextDialog :: Document.Document -> ChatRenderOptions -> Effect Element.Element
renderNewContextDialog document options = do
  dialog <- createElement document "section" "chat-new-context-dialog"
  Element.setAttribute "data-role" "new-context-dialog" dialog
  title <- textElement document "h3" "chat-new-context-title" "New context"
  picker <- renderModelPicker document options
  actions <- createElement document "div" "chat-new-context-actions"
  createButton <- textElement document "button" "chat-new-context-create-button" "Create"
  Element.setAttribute "type" "button" createButton
  Element.setAttribute "data-role" "create-context" createButton
  cancelButton <- textElement document "button" "chat-new-context-cancel-button" "Cancel"
  Element.setAttribute "type" "button" cancelButton
  Element.setAttribute "data-role" "close-new-context" cancelButton
  appendElement actions createButton
  appendElement actions cancelButton
  appendElement dialog title
  appendElement dialog picker
  appendElement dialog actions
  pure dialog

renderModelPicker :: Document.Document -> ChatRenderOptions -> Effect Element.Element
renderModelPicker document options = do
  wrapper <- createElement document "label" "chat-model-picker"
  label <- textElement document "span" "chat-control-label" "Model"
  select <- createElement document "select" "chat-model-select"
  Element.setAttribute "data-role" "model-picker" select
  traverse_ (appendModelOption document options select) options.models
  appendElement wrapper label
  appendElement wrapper select
  pure wrapper

appendModelOption
  :: Document.Document
  -> ChatRenderOptions
  -> Element.Element
  -> ModelDescriptor
  -> Effect Unit
appendModelOption document options select model = do
  let modelValue = modelDescriptorRecord model
  option <- createElement document "option" "chat-model-option"
  Element.setAttribute "value" modelValue.modelId option
  when (options.selectedModelId == Just modelValue.modelId) do
    Element.setAttribute "selected" "selected" option
  setText option (modelValue.displayName <> " - " <> modelValue.selectedEngine)
  appendElement select option

appendContextButton
  :: Document.Document
  -> ChatRenderOptions
  -> Element.Element
  -> ContextSummary
  -> Effect Unit
appendContextButton document options list summary@(ContextSummary record) = do
  item <-
    createElement
      document
      "div"
      (contextItemClass options summary)
  Element.setAttribute "data-context-id" (contextIdRawValue record.contextSummaryId) item
  Element.setAttribute "data-model-id" record.contextSummaryModelId item
  Element.setAttribute "data-soft-deleted" (if record.contextSummarySoftDeleted then "true" else "false") item
  selectButton <- createElement document "button" "chat-context-select"
  Element.setAttribute "type" "button" selectButton
  Element.setAttribute "data-role" "select-context" selectButton
  Element.setAttribute "data-context-id" (contextIdRawValue record.contextSummaryId) selectButton
  Element.setAttribute "data-model-id" record.contextSummaryModelId selectButton
  title <- textElement document "span" "chat-context-title" record.contextSummaryTitle
  modelId <- textElement document "span" "chat-context-model" record.contextSummaryModelId
  appendElement selectButton title
  appendElement selectButton modelId
  appendElement item selectButton
  actions <- createElement document "div" "chat-context-actions"
  renameInput <- createElement document "input" "chat-context-rename-input"
  Element.setAttribute "type" "text" renameInput
  Element.setAttribute "data-role" "context-rename-title" renameInput
  Element.setAttribute "value" record.contextSummaryTitle renameInput
  Element.setAttribute "aria-label" "Context title" renameInput
  renameButton <- textElement document "button" "chat-context-rename-button" "Rename"
  Element.setAttribute "type" "button" renameButton
  Element.setAttribute "data-role" "rename-context" renameButton
  deleteButton <- textElement document "button" "chat-context-delete-button" "Delete"
  Element.setAttribute "type" "button" deleteButton
  Element.setAttribute "data-role" "soft-delete-context" deleteButton
  when record.contextSummarySoftDeleted do
    Element.setAttribute "disabled" "disabled" deleteButton
  appendElement actions renameInput
  appendElement actions renameButton
  appendElement actions deleteButton
  appendElement item actions
  appendElement list item

contextItemClass :: ChatRenderOptions -> ContextSummary -> String
contextItemClass options summary@(ContextSummary record) =
  "chat-context-item"
    <> (if isActiveContext options.activeContextId summary then " active" else "")
    <> (if record.contextSummarySoftDeleted then " soft-deleted" else "")

renderConversationPane
  :: Document.Document
  -> ChatRenderOptions
  -> ChatViewState
  -> Effect Element.Element
renderConversationPane document options state = do
  pane <- createElement document "section" "chat-conversation-pane"
  toolbar <- createElement document "div" "chat-conversation-toolbar"
  title <- textElement document "h2" "chat-section-title" (activeConversationTitle state)
  pending <- textElement document "span" (pendingClass state) (pendingLabel state)
  appendElement toolbar title
  appendElement toolbar pending
  appendElement pane toolbar
  messages <- createElement document "div" "chat-message-list"
  renderMessages document messages state
  appendElement pane messages
  draft <- renderDraftEditor document options state
  appendElement pane draft
  pure pane

renderMessages :: Document.Document -> Element.Element -> ChatViewState -> Effect Unit
renderMessages document container state =
  case state.activeConversation of
    Nothing -> do
      empty <- textElement document "p" "chat-empty-state" "Select or create a context."
      appendElement container empty
    Just (ConversationState conversation) ->
      if conversation.conversationStateMessages == [] then do
        empty <- textElement document "p" "chat-empty-state" "No messages in this context."
        appendElement container empty
      else
        traverse_ (appendConversationMessage document container) conversation.conversationStateMessages

appendConversationMessage
  :: Document.Document
  -> Element.Element
  -> ConversationMessage
  -> Effect Unit
appendConversationMessage document container message = do
  let summary = messageSummary message
  article <- createElement document "article" ("chat-message " <> summary.kind)
  label <- textElement document "div" "chat-message-label" summary.label
  body <- textElement document "p" "chat-message-body" summary.body
  -- Phase 6 Sprint 6.36: mark whether a result message carried real inline
  -- output. The routed E2E asserts text-family rows produce
  -- @data-inline-output="present"@ with real text, so a fabricated or empty
  -- result rendered behind the "No inline output." placeholder
  -- (@data-inline-output="absent"@) can no longer pass a real-output check.
  case messageResultInlinePresence message of
    Just present ->
      Element.setAttribute "data-inline-output" (if present then "present" else "absent") body
    Nothing -> pure unit
  appendElement article label
  appendElement article body
  -- Phase 6 Sprint 6.3: render the per-family inference-result artifact
  -- (image / audio / video / MIDI-or-MusicXML download). Substrate-agnostic:
  -- the rendering keys on the artifact's object-key extension (its artifact
  -- type), never on the substrate id or engine family; `infernix-demo` chose
  -- the engine binding upstream from the active `.dhall`.
  traverse_ (appendResultArtifact document article) (messageResultArtifacts message)
  appendElement container article

-- | Phase 6 Sprint 6.36 — whether a result message carried real inline output.
-- @Just true@ for a result with inline text, @Just false@ for a result without
-- (the "No inline output." placeholder), and @Nothing@ for non-result messages.
messageResultInlinePresence :: ConversationMessage -> Maybe Boolean
messageResultInlinePresence (ConversationMessage message) =
  case message.conversationMessageEvent of
    ConversationInferenceResultEvent (ConversationInferenceResultPayload result) ->
      Just (isJust result.inferenceResultInlineOutput)
    _ -> Nothing

-- | The inference-result artifact object references carried by a result
-- message (empty for prompt / upload / cancel messages and for the inline
-- text families).
messageResultArtifacts :: ConversationMessage -> Array ObjectRef
messageResultArtifacts (ConversationMessage message) =
  case message.conversationMessageEvent of
    ConversationInferenceResultEvent (ConversationInferenceResultPayload result) ->
      result.inferenceResultArtifacts
    _ -> []

-- | Per-family render disposition for a result artifact, derived from the
-- object-key extension only.
data ArtifactRenderKind
  = ImageArtifact
  | AudioArtifact
  | VideoArtifact
  | DownloadArtifact

derive instance eqArtifactRenderKind :: Eq ArtifactRenderKind

artifactRenderKind :: String -> ArtifactRenderKind
artifactRenderKind key
  | anySuffix [ ".png", ".jpg", ".jpeg", ".gif", ".webp" ] key = ImageArtifact
  | anySuffix [ ".wav", ".mp3", ".ogg", ".flac" ] key = AudioArtifact
  | anySuffix [ ".mp4", ".webm", ".mov" ] key = VideoArtifact
  | otherwise = DownloadArtifact

artifactRenderTag :: ArtifactRenderKind -> String
artifactRenderTag kind = case kind of
  ImageArtifact -> "img"
  AudioArtifact -> "audio"
  VideoArtifact -> "video"
  DownloadArtifact -> "a"

artifactRenderKindLabel :: ArtifactRenderKind -> String
artifactRenderKindLabel kind = case kind of
  ImageArtifact -> "image"
  AudioArtifact -> "audio"
  VideoArtifact -> "video"
  DownloadArtifact -> "download"

appendResultArtifact :: Document.Document -> Element.Element -> ObjectRef -> Effect Unit
appendResultArtifact document article (ObjectRef ref) = do
  let kind = artifactRenderKind ref.objectKey
  element <- createElement document (artifactRenderTag kind) ("chat-result-artifact chat-result-" <> artifactRenderKindLabel kind)
  Element.setAttribute "data-object-bucket" ref.objectBucket element
  Element.setAttribute "data-object-key" ref.objectKey element
  Element.setAttribute "data-result-artifact-kind" (artifactRenderKindLabel kind) element
  when (kind == DownloadArtifact) do
    Element.setAttribute "download" "" element
    setText element ("Download " <> ref.objectKey)
  appendElement article element

anySuffix :: Array String -> String -> Boolean
anySuffix suffixes value = isJust (find (\suffix -> isJust (stripSuffix (Pattern suffix) value)) suffixes)

renderDraftEditor
  :: Document.Document
  -> ChatRenderOptions
  -> ChatViewState
  -> Effect Element.Element
renderDraftEditor document options state = do
  form <- createElement document "form" "chat-draft-editor"
  Element.setAttribute "data-role" "chat-draft-editor" form
  textarea <- createElement document "textarea" "chat-draft-input"
  Element.setAttribute "name" "prompt" textarea
  Element.setAttribute "placeholder" "Type a prompt for the selected context" textarea
  setText textarea (fromMaybe "" (options.activeContextId >>= draftTextFor state))
  sendButton <- textElement document "button" "chat-send-button" "Send"
  Element.setAttribute "type" "submit" sendButton
  cancelButton <- textElement document "button" "chat-cancel-button" "Cancel latest prompt"
  Element.setAttribute "type" "button" cancelButton
  Element.setAttribute "data-role" "cancel-latest-prompt" cancelButton
  appendElement form textarea
  appendElement form sendButton
  appendElement form cancelButton
  pure form

messageSummary :: ConversationMessage -> { kind :: String, label :: String, body :: String }
messageSummary (ConversationMessage message) =
  case message.conversationMessageEvent of
    ConversationUserPromptEvent (UserPromptPayload prompt) ->
      { kind: "prompt", label: "Prompt", body: prompt.promptText }
    ConversationInferenceResultEvent (ConversationInferenceResultPayload result) ->
      { kind: "result"
      , label: "Result - " <> result.inferenceResultStatus
      , body:
          case result.inferenceResultError of
            Just error -> inferenceErrorSummary error
            Nothing -> fromMaybe "No inline output." result.inferenceResultInlineOutput
      }
    ConversationCancelEvent (ConversationCancelPayload cancel) ->
      { kind: "cancel"
      , label: "Cancel"
      , body: "Cancel requested for " <> messageIdRawValue cancel.cancelUserPromptMessageId
      }
    ConversationUserUploadEvent (ConversationUserUploadPayload upload) ->
      { kind: "upload"
      , label: "Upload"
      , body: upload.uploadDisplayName <> " (" <> artifactMimeTypeValue upload.uploadMimeType <> ")"
      }

inferenceErrorSummary :: InferenceError -> String
inferenceErrorSummary errorValue =
  case errorValue of
    ModelMemoryLimitExceeded details ->
      "Model "
        <> details.modelMemoryLimitExceededModelId
        <> " requires "
        <> show details.modelMemoryLimitExceededRequiredMib
        <> " MiB; this daemon has "
        <> show details.modelMemoryLimitExceededAvailableMib
        <> " MiB available."

activeConversationTitle :: ChatViewState -> String
activeConversationTitle state =
  case state.activeConversation of
    Nothing -> "Conversation"
    Just (ConversationState conversation) ->
      "Conversation " <> contextIdRawValue conversation.conversationStateContextId

pendingLabel :: ChatViewState -> String
pendingLabel state =
  let pending = pendingPromptCount state
  in
    if pending <= 0 then "No queued prompts"
    else show pending <> " queued prompt" <> if pending == 1 then "" else "s"

pendingClass :: ChatViewState -> String
pendingClass state =
  if pendingPromptCount state >= 2 then "chat-pending-indicator warning" else "chat-pending-indicator"

draftTextFor :: ChatViewState -> ContextId -> Maybe String
draftTextFor state contextId =
  case find (\draft -> draftEntryRawId draft == contextIdRawValue contextId) state.drafts of
    Just (DraftEntry record) -> Just record.draftEntryText
    Nothing -> Nothing

isActiveContext :: Maybe ContextId -> ContextSummary -> Boolean
isActiveContext activeContextId summary =
  case activeContextId of
    Nothing -> false
    Just active -> contextSummaryRawId summary == contextIdRawValue active

messageIdRawValue :: MessageId -> String
messageIdRawValue (MessageId inner) = inner.unMessageId

artifactMimeTypeValue :: ArtifactMimeType -> String
artifactMimeTypeValue (ArtifactMimeType inner) = inner.unArtifactMimeType

createElement :: Document.Document -> String -> String -> Effect Element.Element
createElement document tagName classNameValue = do
  elementValue <- Document.createElement tagName document
  Element.setClassName classNameValue elementValue
  pure elementValue

textElement :: Document.Document -> String -> String -> String -> Effect Element.Element
textElement document tagName classNameValue textValue = do
  elementValue <- createElement document tagName classNameValue
  setText elementValue textValue
  pure elementValue

appendElement :: Element.Element -> Element.Element -> Effect Unit
appendElement parent child =
  void (Node.appendChild (Element.toNode child) (Element.toNode parent))

setText :: Element.Element -> String -> Effect Unit
setText elementValue textValue =
  Node.setTextContent textValue (Element.toNode elementValue)

clearChildren :: Element.Element -> Effect Unit
clearChildren elementValue =
  Node.setTextContent "" (Element.toNode elementValue)
