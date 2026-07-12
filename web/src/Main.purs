module Main where

import Prelude

import Affjax.ResponseFormat as ResponseFormat
import Affjax.StatusCode (StatusCode(..))
import Affjax.Web as AXWeb
import Data.Array (filter, find, head, length, snoc)
import Data.Either (Either(..))
import Data.Foldable (traverse_)
import Data.Maybe (Maybe(..), fromMaybe)
import Effect (Effect)
import Effect.Aff (Aff, launchAff_)
import Effect.Class (liftEffect)
import Effect.Exception (throw)
import Effect.Ref as Ref
import Generated.Contracts
  ( ArtifactKind(..)
  , ArtifactMimeType(..)
  , ClientIdempotencyKey(..)
  , ContextId(..)
  , ContextSummary(..)
  , ConversationEvent(..)
  , ConversationMessage(..)
  , ConversationUserUploadPayload(..)
  , ConversationState(..)
  , ConversationStatePatch(..)
  , DraftEntry(..)
  , MessageId(..)
  , ModelDescriptor
  , ObjectRef(..)
  , UserId(..)
  , UserPromptPayload(..)
  , WsClientMessage(..)
  , WsServerMessage(..)
  , modelDescriptorRecord
  , runtimeMode
  )
import Infernix.Web.ArtifactTransport
  ( UploadedArtifact
  , bindArtifactTransport
  )
import Infernix.Web.Artifacts
  ( ArtifactEntry
  , ArtifactsViewState
  , FilesViewState
  , dispositionFor
  , filesEntriesFromObjectRefs
  , handleArtifactsServerMessage
  , initialArtifactsViewState
  , initialFilesViewState
  , recordArtifactReady
  , renderArtifactsView
  , renderFilesView
  )
import Infernix.Web.Auth
  ( TokenStore
  , beginDeleteAccountRedirect
  , beginLoginRedirect
  , beginLogoutRedirect
  , beginRegisterRedirect
  , clearToken
  , completeRedirect
  , defaultInfernixRealmConfig
  , newTokenStore
  , readToken
  )
import Infernix.Web.Browser
  ( clearStoredActiveContext
  , currentOrigin
  , installForceWebSocketClose
  , newUuid
  , readStoredActiveContext
  , scheduleEffect
  , writeStoredActiveContext
  )
import Infernix.Web.Chat
  ( ChatViewState
  , applyConversationStatePatch
  , conversationForContext
  , handleServerMessage
  , initialChatViewState
  , latestPendingPromptMessageId
  , renderChatView
  , upsertConversationState
  )
import Infernix.Web.DomEvents (bindChatChrome)
import Infernix.Web.FilesTransport (bindFilesActions, refreshFilesList)
import Infernix.Web.Router (Route(..), routePath)
import Infernix.Web.WebSocket
  ( WsConnection
  , close
  , connect
  , defaultWsClientConfig
  , sendClientMessage
  )
import Simple.JSON as JSON
import Web.DOM.Document as Document
import Web.DOM.Element as Element
import Web.DOM.Node as Node
import Web.DOM.NonElementParentNode as NonElementParentNode
import Web.Event.Event as Event
import Web.Event.EventTarget as EventTarget
import Web.HTML (window)
import Web.HTML.Event.EventTypes as EventTypes
import Web.HTML.HTMLDocument as HTMLDocument
import Web.HTML.HTMLElement as HTMLElement
import Web.HTML.Window as Window

type Publication =
  { runtimeMode :: Maybe String
  , controlPlaneContext :: Maybe String
  , daemonLocation :: Maybe String
  , inferenceDispatchMode :: Maybe String
  , edgePort :: Maybe Int
  , routes :: Maybe (Array PublishedRoute)
  }

type PublishedRoute =
  { path :: String
  , purpose :: String
  }

type StoredActiveContext =
  { contextId :: String
  , modelId :: String
  }

type AppState =
  { models :: Array ModelDescriptor
  , publication :: Maybe Publication
  , route :: Route
  , selectedModelId :: Maybe String
  , newContextDialogOpen :: Boolean
  , activeContextId :: Maybe ContextId
  , chat :: ChatViewState
  , artifacts :: ArtifactsViewState
  , files :: FilesViewState
  , authenticated :: Boolean
  , token :: Maybe String
  , wsConnection :: Maybe WsConnection
  , wsGeneration :: Int
  , reconnectAttempts :: Int
  }

type Refs =
  { document :: Document.Document
  , body :: Maybe Element.Element
  , appStatus :: Element.Element
  , loginButton :: Element.Element
  , registerButton :: Element.Element
  , logoutButton :: Element.Element
  , deleteAccountButton :: Element.Element
  , routeChat :: Element.Element
  , routeArtifacts :: Element.Element
  , routeFiles :: Element.Element
  , runtimeModeValue :: Element.Element
  , controlPlaneContext :: Element.Element
  , daemonLocation :: Element.Element
  , inferenceDispatchMode :: Element.Element
  , edgePort :: Element.Element
  , catalogCount :: Element.Element
  , connectionState :: Element.Element
  , routeList :: Element.Element
  , chatRoot :: Element.Element
  , artifactsRoot :: Element.Element
  , filesRoot :: Element.Element
  }

main :: Effect Unit
main = do
  htmlDocument <- Window.document =<< window
  refs <- captureRefs htmlDocument
  tokenStore <- newTokenStore
  maybeToken <- readToken tokenStore
  storedActiveContextJson <- readStoredActiveContext
  let
    storedActiveContext = decodeStoredActiveContext storedActiveContextJson
    restoredActiveContextId =
      case storedActiveContext of
        Just stored -> Just (ContextId { unContextId: stored.contextId })
        Nothing -> Nothing
    restoredSelectedModelId =
      case storedActiveContext of
        Just stored | stored.modelId /= "" -> Just stored.modelId
        _ -> Nothing
    restoredConversation =
      case restoredActiveContextId of
        Just contextId ->
          Just
            ( ConversationState
                { conversationStateContextId: contextId
                , conversationStateMessages: []
                , conversationStatePrefixHash: ""
                }
            )
        Nothing -> Nothing
    restoredConversations =
      case restoredConversation of
        Just conversation -> [ conversation ]
        Nothing -> []
  stateRef <-
    Ref.new
      { models: []
      , publication: Nothing
      , route: RouteChat
      , selectedModelId: restoredSelectedModelId
      , newContextDialogOpen: false
      , activeContextId: restoredActiveContextId
      , chat:
          initialChatViewState
            { activeConversation = restoredConversation
            , conversations = restoredConversations
            }
      , artifacts: initialArtifactsViewState
      , files: initialFilesViewState
      , authenticated: case maybeToken of
          Just _ -> true
          Nothing -> false
      , token: maybeToken
      , wsConnection: Nothing
      , wsGeneration: 0
      , reconnectAttempts: 0
      }
  bindEvents tokenStore stateRef refs
  bindArtifactTransport refs.artifactsRoot (handleUploadedArtifact stateRef refs) (handleArtifactError refs)
  -- The Files view reuses the same upload/download transport, plus list + delete.
  bindArtifactTransport refs.filesRoot (handleUploadedArtifact stateRef refs) (handleArtifactError refs)
  bindFilesActions refs.filesRoot (handleDeletedFile stateRef refs) (handleArtifactError refs)
  renderAll stateRef refs
  completeRedirect tokenStore defaultInfernixRealmConfig (establishAuthenticatedSession stateRef refs)
  case maybeToken of
    Just token -> establishAuthenticatedSession stateRef refs token
    Nothing -> pure unit
  launchAff_ do
    loadPublication stateRef refs
    loadCatalog stateRef refs
  pure unit

decodeStoredActiveContext :: String -> Maybe StoredActiveContext
decodeStoredActiveContext raw =
  case JSON.readJSON raw of
    Right stored | stored.contextId /= "" -> Just stored
    _ -> Nothing

captureRefs :: HTMLDocument.HTMLDocument -> Effect Refs
captureRefs htmlDocument = do
  let document = HTMLDocument.toDocument htmlDocument
  maybeBody <- HTMLDocument.body htmlDocument
  let body = HTMLElement.toElement <$> maybeBody
  appStatus <- requireElement htmlDocument "app-status"
  loginButton <- requireElement htmlDocument "login-button"
  registerButton <- requireElement htmlDocument "register-button"
  logoutButton <- requireElement htmlDocument "logout-button"
  deleteAccountButton <- requireElement htmlDocument "delete-account-button"
  routeChat <- requireElement htmlDocument "route-chat"
  routeArtifacts <- requireElement htmlDocument "route-artifacts"
  routeFiles <- requireElement htmlDocument "route-files"
  runtimeModeValue <- requireElement htmlDocument "runtime-mode"
  controlPlaneContext <- requireElement htmlDocument "control-plane-context"
  daemonLocation <- requireElement htmlDocument "daemon-location"
  inferenceDispatchMode <- requireElement htmlDocument "inference-dispatch-mode"
  edgePort <- requireElement htmlDocument "edge-port"
  catalogCount <- requireElement htmlDocument "catalog-count"
  connectionState <- requireElement htmlDocument "connection-state"
  routeList <- requireElement htmlDocument "route-list"
  chatRoot <- requireElement htmlDocument "chat-root"
  artifactsRoot <- requireElement htmlDocument "artifacts-root"
  filesRoot <- requireElement htmlDocument "files-root"
  pure
    { document
    , body
    , appStatus
    , loginButton
    , registerButton
    , logoutButton
    , deleteAccountButton
    , routeChat
    , routeArtifacts
    , routeFiles
    , runtimeModeValue
    , controlPlaneContext
    , daemonLocation
    , inferenceDispatchMode
    , edgePort
    , catalogCount
    , connectionState
    , routeList
    , chatRoot
    , artifactsRoot
    , filesRoot
    }

bindEvents :: TokenStore -> Ref.Ref AppState -> Refs -> Effect Unit
bindEvents tokenStore stateRef refs = do
  loginListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      beginLoginRedirect defaultInfernixRealmConfig
  EventTarget.addEventListener EventTypes.click loginListener false (Element.toEventTarget refs.loginButton)

  registerListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      beginRegisterRedirect defaultInfernixRealmConfig
  EventTarget.addEventListener EventTypes.click registerListener false (Element.toEventTarget refs.registerButton)

  logoutListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      state <- Ref.read stateRef
      Ref.modify_
        ( \current ->
            current
              { authenticated = false
              , token = Nothing
              , wsConnection = Nothing
              , newContextDialogOpen = false
              , wsGeneration = current.wsGeneration + 1
              , reconnectAttempts = 0
              }
        )
        stateRef
      case state.wsConnection of
        Just connection -> close connection
        Nothing -> pure unit
      clearToken tokenStore
      clearStoredActiveContext
      renderAll stateRef refs
      beginLogoutRedirect defaultInfernixRealmConfig
  EventTarget.addEventListener EventTypes.click logoutListener false (Element.toEventTarget refs.logoutButton)

  deleteAccountListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      state <- Ref.read stateRef
      case state.token of
        Nothing ->
          setStatus refs.appStatus "app-status error" "Sign in before deleting account"
        Just token -> do
          Ref.modify_
            ( \current ->
                current
                  { wsConnection = Nothing
                  , wsGeneration = current.wsGeneration + 1
                  , reconnectAttempts = 0
                  }
            )
            stateRef
          case state.wsConnection of
            Just connection -> close connection
            Nothing -> pure unit
          setStatus refs.appStatus "app-status" "Deleting account"
          beginDeleteAccountRedirect
            defaultInfernixRealmConfig
            token
            \message -> setStatus refs.appStatus "app-status error" message
  EventTarget.addEventListener EventTypes.click deleteAccountListener false (Element.toEventTarget refs.deleteAccountButton)

  chatListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      Ref.modify_ (_ { route = RouteChat }) stateRef
      renderAll stateRef refs
  EventTarget.addEventListener EventTypes.click chatListener false (Element.toEventTarget refs.routeChat)

  artifactsListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      Ref.modify_ (_ { route = RouteArtifacts }) stateRef
      renderAll stateRef refs
  EventTarget.addEventListener EventTypes.click artifactsListener false (Element.toEventTarget refs.routeArtifacts)

  filesListener <-
    EventTarget.eventListener \event -> do
      Event.preventDefault event
      Ref.modify_ (_ { route = RouteFiles }) stateRef
      renderAll stateRef refs
      refreshFiles stateRef refs
  EventTarget.addEventListener EventTypes.click filesListener false (Element.toEventTarget refs.routeFiles)

  bindChatChrome
    refs.chatRoot
    (openNewContextDialog stateRef refs)
    (createContext stateRef refs)
    (closeNewContextDialog stateRef refs)
    (renameContext stateRef refs)
    (softDeleteContext stateRef refs)
    (selectContext stateRef refs)
    (selectModel stateRef refs)
    (submitPrompt stateRef refs)
    (cancelLatestPrompt stateRef refs)
    (updateDraft stateRef refs)

establishAuthenticatedSession :: Ref.Ref AppState -> Refs -> String -> Effect Unit
establishAuthenticatedSession stateRef refs token =
  mountAuthenticatedSession true stateRef refs token

mountAuthenticatedSession :: Boolean -> Ref.Ref AppState -> Refs -> String -> Effect Unit
mountAuthenticatedSession resetReconnectAttempts stateRef refs token = do
  previous <- Ref.read stateRef
  let nextGeneration = previous.wsGeneration + 1
  Ref.modify_
    ( \current ->
        current
          { authenticated = true
          , token = Just token
          , wsConnection = Nothing
          , wsGeneration = nextGeneration
          , reconnectAttempts =
              if resetReconnectAttempts then 0 else current.reconnectAttempts
          }
    )
    stateRef
  case previous.wsConnection of
    Just connection -> close connection
    Nothing -> pure unit
  origin <- currentOrigin
  latest <- Ref.read stateRef
  connection <-
    connect
      ( (defaultWsClientConfig origin token)
          { initialMessages = initialSessionMessages latest
          }
      )
      ( \message -> do
        current <- Ref.read stateRef
        if current.wsGeneration == nextGeneration then do
          Ref.modify_ (applyServerMessage message) stateRef
          renderServerMessage message stateRef refs
        else
          pure unit
      )
      (handleSocketClose stateRef refs nextGeneration)
  installForceWebSocketClose (close connection)
  Ref.modify_
    ( \current ->
        if current.wsGeneration == nextGeneration then
          current { wsConnection = Just connection }
        else
          current
    )
    stateRef
  setStatus refs.appStatus "app-status ready" "Ready"
  renderAll stateRef refs

initialSessionMessages :: AppState -> Array WsClientMessage
initialSessionMessages state =
  case state.activeContextId of
    Just contextId ->
      [ clientHelloMessage
      , ClientSubscribeContext
          { clientSubscribeContextId: contextId
          }
      ] <> reconnectDraftMessages state contextId
    Nothing -> [ clientHelloMessage ]

clientHelloMessage :: WsClientMessage
clientHelloMessage =
  ClientHello
    { clientHelloUserId: UserId { unUserId: "" }
    }

reconnectDraftMessages :: AppState -> ContextId -> Array WsClientMessage
reconnectDraftMessages state contextId =
  case draftTextForContext contextId state.chat of
    Just draftText | draftText /= "" ->
      [ ClientUpdateDraft
          { clientUpdateDraftContextId: contextId
          , clientUpdateDraftText: draftText
          }
      ]
    _ -> []

draftTextForContext :: ContextId -> ChatViewState -> Maybe String
draftTextForContext contextId chat =
  case find (draftMatchesContext contextId) chat.drafts of
    Just (DraftEntry draft) -> Just draft.draftEntryText
    Nothing -> Nothing

draftMatchesContext :: ContextId -> DraftEntry -> Boolean
draftMatchesContext contextId (DraftEntry draft) =
  contextIdRawValue draft.draftEntryContextId == contextIdRawValue contextId

contextIdRawValue :: ContextId -> String
contextIdRawValue (ContextId inner) = inner.unContextId

conversationTargetsContext :: ContextId -> ConversationState -> Boolean
conversationTargetsContext contextId (ConversationState conversation) =
  contextIdRawValue contextId == contextIdRawValue conversation.conversationStateContextId

handleSocketClose :: Ref.Ref AppState -> Refs -> Int -> String -> Effect Unit
handleSocketClose stateRef refs generation _reason = do
  state <- Ref.read stateRef
  if state.authenticated && state.wsGeneration == generation then do
    let nextAttempts = state.reconnectAttempts + 1
    Ref.modify_
      ( \current ->
          if current.wsGeneration == generation then
            current { wsConnection = Nothing, reconnectAttempts = nextAttempts }
          else
            current
      )
      stateRef
    renderAll stateRef refs
    scheduleEffect (reconnectDelayMs nextAttempts) do
      scheduled <- Ref.read stateRef
      case scheduled.token of
        Just token
          | scheduled.authenticated && scheduled.wsGeneration == generation ->
              mountAuthenticatedSession false stateRef refs token
        _ -> pure unit
  else
    pure unit

reconnectDelayMs :: Int -> Int
reconnectDelayMs attempt =
  if attempt <= 1 then 500
  else if attempt == 2 then 1000
  else if attempt == 3 then 2000
  else 5000

applyServerMessage :: WsServerMessage -> AppState -> AppState
applyServerMessage message state =
  state
    { chat = handleServerMessage state.activeContextId message state.chat
    , artifacts = handleArtifactsServerMessage message state.artifacts
    }

createContext :: Ref.Ref AppState -> Refs -> Effect Unit
createContext stateRef refs = do
  state <- Ref.read stateRef
  case state.selectedModelId of
    Nothing ->
      setStatus refs.appStatus "app-status error" "Model catalog is not loaded"
    Just modelId -> do
      uuid <- newUuid
      let
        contextIdText = "ctx-" <> uuid
        contextId = ContextId { unContextId: contextIdText }
        title = "New context"
        summary =
          ContextSummary
            { contextSummaryId: contextId
            , contextSummaryModelId: modelId
            , contextSummaryTitle: title
            , contextSummarySoftDeleted: false
            }
        conversation =
          ConversationState
            { conversationStateContextId: contextId
            , conversationStateMessages: []
            , conversationStatePrefixHash: ""
            }
      case state.wsConnection of
        Just connection -> do
          sendClientMessage
            connection
            ( ClientCreateContext
                { clientCreateContextId: contextId
                , clientCreateContextModelId: modelId
                , clientCreateContextTitle: title
                }
            )
          subscribeContext connection contextId
        Nothing -> pure unit
      writeStoredActiveContext contextIdText modelId
      Ref.modify_
        ( \current ->
            current
              { activeContextId = Just contextId
              , newContextDialogOpen = false
              , chat =
                  current.chat
                    { contexts = snoc current.chat.contexts summary
                    , activeConversation = Just conversation
                    , conversations = upsertConversationState conversation current.chat.conversations
                    }
              }
        )
        stateRef
      renderAll stateRef refs

openNewContextDialog :: Ref.Ref AppState -> Refs -> Effect Unit
openNewContextDialog stateRef refs = do
  Ref.modify_ (_ { newContextDialogOpen = true }) stateRef
  renderAll stateRef refs

closeNewContextDialog :: Ref.Ref AppState -> Refs -> Effect Unit
closeNewContextDialog stateRef refs = do
  Ref.modify_ (_ { newContextDialogOpen = false }) stateRef
  renderAll stateRef refs

renameContext :: Ref.Ref AppState -> Refs -> String -> String -> Effect Unit
renameContext stateRef refs contextIdText title = do
  state <- Ref.read stateRef
  if contextIdText == "" then
    setStatus refs.appStatus "app-status error" "Select a context before renaming"
  else if title == "" then
    setStatus refs.appStatus "app-status error" "Context title is empty"
  else
    case state.wsConnection of
      Just connection -> do
        sendClientMessage
          connection
          ( ClientRenameContext
              { clientRenameContextId: ContextId { unContextId: contextIdText }
              , clientRenameContextTitle: title
              }
          )
        setStatus refs.appStatus "app-status ready" "Rename requested"
      Nothing ->
        setStatus refs.appStatus "app-status error" "WebSocket is not connected"

softDeleteContext :: Ref.Ref AppState -> Refs -> String -> Effect Unit
softDeleteContext stateRef refs contextIdText = do
  state <- Ref.read stateRef
  if contextIdText == "" then
    setStatus refs.appStatus "app-status error" "Select a context before deleting"
  else
    case state.wsConnection of
      Just connection -> do
        sendClientMessage
          connection
          ( ClientSoftDeleteContext
              { clientSoftDeleteContextId: ContextId { unContextId: contextIdText }
              }
          )
        setStatus refs.appStatus "app-status ready" "Delete requested"
      Nothing ->
        setStatus refs.appStatus "app-status error" "WebSocket is not connected"

selectContext :: Ref.Ref AppState -> Refs -> String -> String -> Effect Unit
selectContext stateRef refs contextIdText modelId = do
  currentState <- Ref.read stateRef
  let
    contextId = ContextId { unContextId: contextIdText }
    selectedContextModelId = if modelId == "" then fromMaybe "" currentState.selectedModelId else modelId
    conversation =
      ConversationState
        { conversationStateContextId: contextId
        , conversationStateMessages: []
        , conversationStatePrefixHash: ""
        }
  writeStoredActiveContext contextIdText selectedContextModelId
  Ref.modify_
    ( \state ->
        state
          { activeContextId = Just contextId
          , newContextDialogOpen = false
          , selectedModelId = if selectedContextModelId == "" then state.selectedModelId else Just selectedContextModelId
          , chat =
              let
                selectedConversation =
                  fromMaybe conversation (conversationForContext contextId state.chat)
              in
                state.chat
                  { activeConversation = Just selectedConversation
                  , conversations = upsertConversationState selectedConversation state.chat.conversations
                  }
          }
    )
    stateRef
  case currentState.wsConnection of
    Just connection -> subscribeContext connection contextId
    Nothing -> pure unit
  renderAll stateRef refs

subscribeContext :: WsConnection -> ContextId -> Effect Unit
subscribeContext connection contextId =
  sendClientMessage
    connection
    ( ClientSubscribeContext
        { clientSubscribeContextId: contextId
        }
    )

selectModel :: Ref.Ref AppState -> Refs -> String -> Effect Unit
selectModel stateRef refs modelId = do
  Ref.modify_ (_ { selectedModelId = if modelId == "" then Nothing else Just modelId }) stateRef
  renderAll stateRef refs

submitPrompt :: Ref.Ref AppState -> Refs -> String -> Effect Unit
submitPrompt stateRef refs promptText = do
  state <- Ref.read stateRef
  case state.activeContextId of
    Nothing ->
      setStatus refs.appStatus "app-status error" "Create or select a context before sending a prompt"
    Just contextId ->
      if promptText == "" then
        setStatus refs.appStatus "app-status error" "Prompt text is empty"
      else do
        uuid <- newUuid
        let
          idempotencyKey = ClientIdempotencyKey { unClientIdempotencyKey: "prompt-" <> uuid }
          payload =
            UserPromptPayload
              { promptText: promptText
              , promptClientIdempotencyKey: idempotencyKey
              , promptUserUploads: uploadedObjectRefsForContext contextId state.artifacts
              }
        case state.wsConnection of
          Just connection -> do
            sendClientMessage
              connection
              ( ClientSubmitPrompt
                  { clientSubmitPromptContextId: contextId
                  , clientSubmitPromptPayload: payload
                  }
              )
            sendClientMessage
              connection
              ( ClientUpdateDraft
                  { clientUpdateDraftContextId: contextId
                  , clientUpdateDraftText: ""
                  }
              )
            Ref.modify_
              ( \current ->
                  current
                    { chat =
                        seedSubmittedPrompt contextId uuid payload
                          (dropDraftForContext contextId current.chat)
                    }
              )
              stateRef
            setStatus refs.appStatus "app-status ready" "Prompt sent"
            renderAll stateRef refs
          Nothing ->
            setStatus refs.appStatus "app-status error" "WebSocket is not connected"

cancelLatestPrompt :: Ref.Ref AppState -> Refs -> Effect Unit
cancelLatestPrompt stateRef refs = do
  state <- Ref.read stateRef
  case state.activeContextId of
    Nothing ->
      setStatus refs.appStatus "app-status error" "Create or select a context before cancelling"
    Just contextId ->
      case latestPendingPromptMessageId state.chat of
        Nothing ->
          setStatus refs.appStatus "app-status error" "No prompt is available to cancel"
        Just promptMessageId -> do
          case state.wsConnection of
            Just connection -> do
              sendClientMessage
                connection
                ( ClientCancelPrompt
                    { clientCancelPromptContextId: contextId
                    , clientCancelPromptUserPromptMessageId: promptMessageId
                    }
              )
              setStatus refs.appStatus "app-status ready" "Cancel requested"
            Nothing ->
              setStatus refs.appStatus "app-status error" "WebSocket is not connected"

updateDraft :: Ref.Ref AppState -> Refs -> String -> Effect Unit
updateDraft stateRef _refs draftText = do
  state <- Ref.read stateRef
  case state.activeContextId of
    Nothing -> pure unit
    Just contextId -> do
      case state.wsConnection of
        Just connection ->
          sendClientMessage
            connection
            ( ClientUpdateDraft
                { clientUpdateDraftContextId: contextId
                , clientUpdateDraftText: draftText
                }
            )
        Nothing -> pure unit
      Ref.modify_
        ( \current ->
            current
              { chat =
                  if draftText == "" then
                    dropDraftForContext contextId current.chat
                  else
                    upsertDraftForContext contextId draftText current.chat
              }
        )
        stateRef

seedSubmittedPrompt :: ContextId -> String -> UserPromptPayload -> ChatViewState -> ChatViewState
seedSubmittedPrompt contextId uuid payload chat =
  let
    optimisticMessage =
      ConversationMessage
        { conversationMessageId: MessageId { unMessageId: "local-" <> uuid }
        , conversationMessageEvent: ConversationUserPromptEvent payload
        }
    patch =
      ConversationStateAppendMessage
        { appendMessage: optimisticMessage
        , appendNewPrefixHash: "local-" <> uuid
        }
    baseConversation =
      ConversationState
        { conversationStateContextId: contextId
        , conversationStateMessages: []
        , conversationStatePrefixHash: ""
        }
    targetConversation =
      case conversationForContext contextId chat of
        Just conversation -> conversation
        Nothing ->
          case chat.activeConversation of
            Just conversation | conversationTargetsContext contextId conversation -> conversation
            _ -> baseConversation
    patchedConversation =
      applyConversationStatePatch patch targetConversation
  in
    chat
      { activeConversation = Just patchedConversation
      , conversations = upsertConversationState patchedConversation chat.conversations
      }

handleUploadedArtifact :: Ref.Ref AppState -> Refs -> String -> Effect Unit
handleUploadedArtifact stateRef refs rawPayload =
  case JSON.readJSON rawPayload of
    Left decodeError ->
      setStatus refs.appStatus "app-status error" ("Unable to decode uploaded artifact: " <> show decodeError)
    Right uploaded -> do
      state <- Ref.read stateRef
      let entry = uploadedArtifactEntry uploaded
      case state.wsConnection of
        Just connection ->
          sendClientMessage
            connection
            ( ClientRecordUpload
                { clientRecordUploadContextId: entry.contextId
                , clientRecordUploadPayload: uploadedArtifactPayload uploaded
                }
            )
        Nothing -> pure unit
      Ref.modify_
        ( \current ->
            current
              { artifacts =
                  recordArtifactReady entry current.artifacts
              }
        )
        stateRef
      setStatus refs.appStatus "app-status ready" "Uploaded"
      renderAll stateRef refs
      refreshFiles stateRef refs

uploadedArtifactEntry :: UploadedArtifact -> ArtifactEntry
uploadedArtifactEntry uploaded =
  let
    mimeType = uploaded.mimeType
  in
    { contextId: ContextId { unContextId: uploaded.contextId }
    , objectRef: uploadedObjectRef uploaded
    , kind: ArtifactKindUpload
    , mimeType: mimeType
    , disposition: dispositionFor mimeType
    }

uploadedArtifactPayload :: UploadedArtifact -> ConversationUserUploadPayload
uploadedArtifactPayload uploaded =
  ConversationUserUploadPayload
    { uploadObjectRef: uploadedObjectRef uploaded
    , uploadMimeType: ArtifactMimeType { unArtifactMimeType: uploaded.mimeType }
    , uploadDisplayName: uploaded.displayName
    }

uploadedObjectRef :: UploadedArtifact -> ObjectRef
uploadedObjectRef uploaded =
  ObjectRef
    { objectBucket: uploaded.objectBucket
    , objectKey: uploaded.objectKey
    }

uploadedObjectRefsForContext :: ContextId -> ArtifactsViewState -> Array ObjectRef
uploadedObjectRefsForContext contextId artifacts =
  map _.objectRef
    ( filter
        ( \entry ->
            entry.contextId == contextId && entry.kind == ArtifactKindUpload
        )
        artifacts.entries
    )

dropDraftForContext :: ContextId -> ChatViewState -> ChatViewState
dropDraftForContext contextId chat =
  chat { drafts = filter (not <<< draftEntryMatches contextId) chat.drafts }

upsertDraftForContext :: ContextId -> String -> ChatViewState -> ChatViewState
upsertDraftForContext contextId draftText chat =
  let
    nextDraft =
      DraftEntry
        { draftEntryContextId: contextId
        , draftEntryText: draftText
        }
    replaced =
      map
        ( \draft ->
            if draftEntryMatches contextId draft then nextDraft else draft
        )
        chat.drafts
    matched = filter (draftEntryMatches contextId) chat.drafts
  in
    chat
      { drafts =
          if matched == [] then
            snoc chat.drafts nextDraft
          else
            replaced
      }

draftEntryMatches :: ContextId -> DraftEntry -> Boolean
draftEntryMatches contextId (DraftEntry draft) =
  draft.draftEntryContextId == contextId

handleArtifactError :: Refs -> String -> Effect Unit
handleArtifactError refs message =
  setStatus refs.appStatus "app-status error" message

-- | Phase 7 Sprint 7.26 — refresh the per-user Files list from
-- | @GET /api/objects/list@ (scoped server-side to the caller's prefix).
refreshFiles :: Ref.Ref AppState -> Refs -> Effect Unit
refreshFiles stateRef refs = do
  state <- Ref.read stateRef
  if state.authenticated then
    refreshFilesList (handleFilesLoaded stateRef refs) (handleArtifactError refs)
  else
    pure unit

handleFilesLoaded :: Ref.Ref AppState -> Refs -> String -> Effect Unit
handleFilesLoaded stateRef refs rawBody =
  case JSON.readJSON rawBody of
    Left decodeError ->
      setStatus refs.appStatus "app-status error" ("Unable to decode file list: " <> show decodeError)
    Right refsList -> do
      let entries = filesEntriesFromObjectRefs (refsList :: Array ObjectRef)
      Ref.modify_
        ( \current ->
            current { files = current.files { entries = entries, status = show (length entries) <> " files" } }
        )
        stateRef
      renderAll stateRef refs

handleDeletedFile :: Ref.Ref AppState -> Refs -> String -> Effect Unit
handleDeletedFile stateRef refs _objectKey = do
  setStatus refs.appStatus "app-status ready" "File deleted"
  refreshFiles stateRef refs

loadPublication :: Ref.Ref AppState -> Refs -> Aff Unit
loadPublication stateRef refs = do
  response <- AXWeb.get ResponseFormat.string "/api/publication"
  case response of
    Left requestError ->
      liftEffect do
        Ref.modify_ (_ { publication = Nothing }) stateRef
        setStatus refs.appStatus "app-status error" (AXWeb.printError requestError)
        renderAll stateRef refs
    Right httpResponse ->
      if statusCode httpResponse.status >= 400 then
        liftEffect do
          Ref.modify_ (_ { publication = Nothing }) stateRef
          setStatus refs.appStatus "app-status error" ("Publication request failed with " <> show (statusCode httpResponse.status))
          renderAll stateRef refs
      else
        case JSON.readJSON httpResponse.body of
          Left decodeError ->
            liftEffect do
              Ref.modify_ (_ { publication = Nothing }) stateRef
              setStatus refs.appStatus "app-status error" ("Unable to decode publication: " <> show decodeError)
              renderAll stateRef refs
          Right publicationValue ->
            liftEffect do
              Ref.modify_ (_ { publication = Just publicationValue }) stateRef
              renderAll stateRef refs

loadCatalog :: Ref.Ref AppState -> Refs -> Aff Unit
loadCatalog stateRef refs = do
  response <- AXWeb.get ResponseFormat.string "/api/models"
  case response of
    Left requestError ->
      liftEffect do
        Ref.modify_ (_ { models = [], selectedModelId = Nothing }) stateRef
        setStatus refs.appStatus "app-status error" (AXWeb.printError requestError)
        renderAll stateRef refs
    Right httpResponse ->
      if statusCode httpResponse.status >= 400 then
        liftEffect do
          Ref.modify_ (_ { models = [], selectedModelId = Nothing }) stateRef
          setStatus refs.appStatus "app-status error" ("Catalog request failed with " <> show (statusCode httpResponse.status))
          renderAll stateRef refs
      else
        case JSON.readJSON httpResponse.body of
          Left decodeError ->
            liftEffect do
              Ref.modify_ (_ { models = [], selectedModelId = Nothing }) stateRef
              setStatus refs.appStatus "app-status error" ("Unable to decode catalog: " <> show decodeError)
              renderAll stateRef refs
          Right modelsValue ->
            liftEffect do
              Ref.modify_ (updateCatalog modelsValue) stateRef
              setStatus refs.appStatus "app-status ready" "Ready"
              renderAll stateRef refs

updateCatalog :: Array ModelDescriptor -> AppState -> AppState
updateCatalog modelsValue state =
  state
    { models = modelsValue
    , selectedModelId =
        case state.selectedModelId of
          Just existing -> Just existing
          Nothing -> (_.modelId <<< modelDescriptorRecord) <$> head modelsValue
    }

renderAll :: Ref.Ref AppState -> Refs -> Effect Unit
renderAll stateRef refs = do
  state <- Ref.read stateRef
  renderAuthGate refs state
  renderSummary refs state
  renderRoutes refs.document refs.routeList state.publication
  renderRouteChrome refs state.route
  renderChatSection refs state
  renderArtifactsSection refs state
  renderFilesSection refs state

renderAuthGate :: Refs -> AppState -> Effect Unit
renderAuthGate refs state =
  case refs.body of
    Just bodyElement ->
      Element.setClassName
        (if state.authenticated then "auth-signed-in" else "auth-signed-out")
        bodyElement
    Nothing -> pure unit

renderServerMessage :: WsServerMessage -> Ref.Ref AppState -> Refs -> Effect Unit
renderServerMessage message stateRef refs = do
  state <- Ref.read stateRef
  renderSummary refs state
  case message of
    ServerConversationSnapshot _ -> renderChatSection refs state
    ServerConversationPatch _ -> renderChatSection refs state
    ServerContextListSnapshot _ -> renderChatSection refs state
    ServerContextListPatch _ -> renderChatSection refs state
    ServerDraftMapSnapshot _ -> renderChatSection refs state
    ServerDraftMapPatch _ -> renderChatSection refs state
    ServerArtifactReady _ -> renderArtifactsSection refs state
    ServerInferenceProgress _ -> renderChatSection refs state
    ServerError _ -> pure unit

renderChatSection :: Refs -> AppState -> Effect Unit
renderChatSection refs state =
  renderChatView
    refs.document
    refs.chatRoot
    { activeContextId: state.activeContextId
    , selectedModelId: state.selectedModelId
    , models: state.models
    , newContextDialogOpen: state.newContextDialogOpen
    }
    state.chat

renderArtifactsSection :: Refs -> AppState -> Effect Unit
renderArtifactsSection refs state =
  renderArtifactsView
    refs.document
    refs.artifactsRoot
    { activeContextId: state.activeContextId }
    state.artifacts

renderFilesSection :: Refs -> AppState -> Effect Unit
renderFilesSection refs state =
  renderFilesView
    refs.document
    refs.filesRoot
    { activeContextId: state.activeContextId }
    state.files

renderSummary :: Refs -> AppState -> Effect Unit
renderSummary refs state = do
  let publicationRuntime =
        state.publication >>= _.runtimeMode
      renderedRuntime = fromMaybe runtimeMode publicationRuntime
      renderedControlPlane =
        fromMaybe "Unavailable" (state.publication >>= _.controlPlaneContext)
      renderedDaemon =
        fromMaybe "Unavailable" (state.publication >>= _.daemonLocation)
      renderedDispatch =
        fromMaybe "Unavailable" (state.publication >>= _.inferenceDispatchMode)
      renderedEdgePort =
        case state.publication >>= _.edgePort of
          Just port -> show port
          Nothing -> "Unavailable"
      renderedConnection =
        if state.authenticated then "Authenticated" else "Signed out"
  setText refs.runtimeModeValue renderedRuntime
  setText refs.controlPlaneContext renderedControlPlane
  setText refs.daemonLocation renderedDaemon
  setText refs.inferenceDispatchMode renderedDispatch
  setText refs.edgePort renderedEdgePort
  setText refs.catalogCount (show (length state.models))
  setText refs.connectionState renderedConnection

renderRoutes :: Document.Document -> Element.Element -> Maybe Publication -> Effect Unit
renderRoutes document container maybePublication = do
  clearChildren container
  case maybePublication >>= _.routes of
    Just routes ->
      if length routes == 0 then appendRoutePlaceholder document container
      else traverse_ (appendRoute document container) routes
    Nothing -> appendRoutePlaceholder document container

appendRoute :: Document.Document -> Element.Element -> PublishedRoute -> Effect Unit
appendRoute document container route = do
  item <- Document.createElement "li" document
  setText item (route.path <> " -> " <> route.purpose)
  appendElement container item

appendRoutePlaceholder :: Document.Document -> Element.Element -> Effect Unit
appendRoutePlaceholder document container = do
  item <- Document.createElement "li" document
  setText item "Unavailable"
  appendElement container item

renderRouteChrome :: Refs -> Route -> Effect Unit
renderRouteChrome refs route = do
  Element.setClassName (routeButtonClass RouteChat route) refs.routeChat
  Element.setClassName (routeButtonClass RouteArtifacts route) refs.routeArtifacts
  Element.setClassName (routeButtonClass RouteFiles route) refs.routeFiles
  Element.setAttribute "href" (routePath RouteChat) refs.routeChat
  Element.setAttribute "href" (routePath RouteArtifacts) refs.routeArtifacts
  Element.setAttribute "href" (routePath RouteFiles) refs.routeFiles

routeButtonClass :: Route -> Route -> String
routeButtonClass candidate active =
  if candidate == active then "app-tab active" else "app-tab"

requireElement :: HTMLDocument.HTMLDocument -> String -> Effect Element.Element
requireElement htmlDocument elementId = do
  maybeElement <- NonElementParentNode.getElementById elementId (HTMLDocument.toNonElementParentNode htmlDocument)
  case maybeElement of
    Just elementValue -> pure elementValue
    Nothing -> throw ("Missing required element #" <> elementId)

statusCode :: StatusCode -> Int
statusCode (StatusCode value) = value

setStatus :: Element.Element -> String -> String -> Effect Unit
setStatus elementValue classNameValue message =
  Element.setClassName classNameValue elementValue *> setText elementValue message

setText :: Element.Element -> String -> Effect Unit
setText elementValue message =
  Node.setTextContent message (Element.toNode elementValue)

clearChildren :: Element.Element -> Effect Unit
clearChildren elementValue =
  Node.setTextContent "" (Element.toNode elementValue)

appendElement :: Element.Element -> Element.Element -> Effect Unit
appendElement parent child =
  void (Node.appendChild (Element.toNode child) (Element.toNode parent))
