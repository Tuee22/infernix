{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Pulsar
  ( DemoClientMessagePublication (..),
    DemoClientMessageError (..),
    PulsarTransport (..),
    PulsarWebSocketBase (..),
    RawTopicMessage (..),
    compactTopicAndWait,
    clearServiceReadinessMarker,
    consumeTopicForever,
    DemoUserTopicDeletion (..),
    authorizedGeneratedResultObjectRefs,
    deleteDemoUserTopics,
    deleteDemoUserTopicsWithAttemptBudget,
    domainResultToProto,
    discoverPulsarTransport,
    planDemoClientMessagePublications,
    publishDemoClientMessage,
    streamDemoContextConversation,
    streamDemoUserMetadata,
    publishModelBootstrapRequest,
    publishRawTopicPayload,
    validateDemoClientMessageCatalog,
    ensureRegisteredSchemasWithRetry,
    ensureSchemaMarkers,
    modelCacheBootstrapRetryableError,
    modelBootstrapReadyWaitMaxSeconds,
    reconcileStartupTopicsWithRetry,
    reconcileSupportedNamespacesWithRetry,
    isMultiFileModelRepoUrl,
    isPackageBackedNativeModel,
    renderPulsarWebSocketBase,
    publishInferenceRequest,
    protoResultToDomain,
    parseMessageIdToSequenceId,
    inferenceRequestProducerNameForFields,
    inferenceRequestSequenceId,
    inferenceRequestSequenceIdForFields,
    readNamespaceCompactionThreshold,
    rawTopicInferenceRequestIds,
    readRawTopicPayloads,
    rawTopicInferenceRequestPromptIds,
    rawTopicInferenceResultCausalRefs,
    readPublishedInferenceResultMaybe,
    isRetryablePulsarWebSocketClientFailure,
    drainTopic,
    drainTopicWithKVCache,
    buildServiceConsumerSocketPath,
    serviceConsumerAckTimeoutMillis,
    requireTopicRef,
    runDispatcherLoop,
    runModelBootstrapLoop,
    runResultBridgeLoop,
    sweepEagerModelCache,
    waitForEagerModelCacheReady,
    schemaMarkerPath,
    serviceConsumerSubscriptionType,
    serviceConsumerSubscriptionTypeForTopic,
    serviceConsumerName,
    serviceReadinessMarkerPath,
    startupTopicsForDemoConfig,
    topicDirectoryPath,
    writeServiceReadinessMarker,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (forkIO, killThread, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar)
import Control.Exception (Exception, SomeAsyncException, SomeException, displayException, finally, fromException, throwIO, try)
import Control.Monad (filterM, forM_, forever, unless, void, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Crypto.Random (getRandomBytes)
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON,
    Value,
    eitherDecode,
    eitherDecodeStrict',
    encode,
    object,
    withObject,
    (.:),
    (.:?),
    (.=),
  )
import Data.Bits (shiftL, (.&.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.IORef (IORef, atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (intercalate, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe, isJust, isNothing, listToMaybe)
import Data.ProtoLens (Message, decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime, parseTimeM)
import Data.Word (Word8)
import Infernix.Bootstrap.Models qualified as BootstrapModels
import Infernix.Bridge.Result qualified as ResultBridge
import Infernix.ClusterConfig
  ( ClusterConfig (..),
    DemoBackendWiring (..),
    PulsarWiring (..),
  )
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config
import Infernix.Conversation.Hash (PrefixHash (..))
import Infernix.Conversation.Reducer
  ( ReducerState,
    StepOutcome (StepAdvanced, StepDropped),
    initialReducerState,
    stepReducer,
  )
import Infernix.Conversation.Topic qualified as ConversationTopic
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Dispatch.ContextModelMap (ContextModelMap)
import Infernix.Dispatch.ContextModelMap qualified as ContextModelMap
import Infernix.Dispatch.SingleFlight qualified as Dispatch
import Infernix.HostConfig qualified as HostConfig
import Infernix.Models
  ( enginePoolForModel,
    enginePoolTopicForMode,
    findModel,
    modelRequiresInputObject,
  )
import Infernix.Objects.Layout qualified as ObjLayout
import Infernix.Objects.Presigned qualified as Presigned
import Infernix.Python (ensurePoetryExecutable)
import Infernix.Runtime (executeInferenceWithKVCache)
import Infernix.Runtime.KVCache qualified as KVCache
import Infernix.Runtime.Pulsar.Failover qualified as PulsarFailover
import Infernix.Runtime.Worker (EngineCommandOverrideMap)
import Infernix.SecretsConfig qualified as Secrets
import Infernix.Storage (formatTimestamp, parseTimestamp, readPulsarHttpPortMaybe)
import Infernix.Types
import Infernix.Web.Contracts qualified as Contracts
import Lens.Family2 (set, view)
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS, RequestBodyStream),
    brRead,
    defaultManagerSettings,
    httpLbs,
    method,
    newManager,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
    withResponse,
  )
import Network.HTTP.Client.TLS (tlsManagerSettings)
import Network.HTTP.Types.Status (statusCode)
import Network.WebSockets qualified as WebSockets
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getTemporaryDirectory,
    listDirectory,
    removeFile,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (<.>), (</>))
import System.IO (Handle, IOMode (ReadMode), hClose, hFileSize, hPutStrLn, openBinaryTempFile, stderr, withBinaryFile)
import System.Posix.Process (getProcessID)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)

data PulsarTransport = PulsarTransport
  { pulsarAdminBaseUrl :: Maybe String,
    pulsarWebSocketBase :: PulsarWebSocketBase
  }

data PulsarWebSocketBase = PulsarWebSocketBase
  { pulsarWsHost :: String,
    pulsarWsPort :: Int,
    pulsarWsPathPrefix :: String
  }

data TopicRef = TopicRef
  { topicDomain :: Text.Text,
    topicTenant :: Text.Text,
    topicNamespace :: Text.Text,
    topicName :: Text.Text
  }

data ProducerResponse = ProducerResponse
  { producerResult :: Text.Text,
    producerErrorMessage :: Maybe Text.Text
  }

data PulsarEnvelope = PulsarEnvelope
  { envelopeMessageId :: Text.Text,
    envelopeKey :: Maybe Text.Text,
    envelopePayload :: Text.Text
  }

data RawTopicMessage = RawTopicMessage
  { rawTopicMessageId :: Text.Text,
    rawTopicMessageKey :: Maybe Text.Text,
    rawTopicMessagePayload :: ByteString.ByteString
  }
  deriving (Eq, Show)

data DemoUserTopicDeletion = DemoUserTopicDeletion
  { demoUserTopicDeletionDeleted :: Int,
    demoUserTopicDeletionRemaining :: [Text.Text]
  }
  deriving (Eq, Show)

data LongRunningProcessStatus = LongRunningProcessStatus
  { longRunningProcessStatus :: Text.Text,
    longRunningProcessLastError :: Maybe Text.Text
  }
  deriving (Eq, Show)

newtype HostDiscoveredPublication = HostDiscoveredPublication
  { hostPublicationClusterPresent :: Bool
  }

instance FromJSON ProducerResponse where
  parseJSON = withObject "ProducerResponse" $ \value ->
    ProducerResponse
      <$> value .: "result"
      <*> value .:? "errorMsg"

instance FromJSON PulsarEnvelope where
  parseJSON = withObject "PulsarEnvelope" $ \value ->
    PulsarEnvelope
      <$> value .: "messageId"
      <*> ((value .:? "key") <|> (value .:? "partitionKey"))
      <*> value .: "payload"

instance FromJSON HostDiscoveredPublication where
  parseJSON = withObject "HostDiscoveredPublication" $ \value ->
    HostDiscoveredPublication
      <$> value .: "clusterPresent"

instance FromJSON LongRunningProcessStatus where
  parseJSON = withObject "LongRunningProcessStatus" $ \value ->
    LongRunningProcessStatus
      <$> value .: "status"
      <*> value .:? "lastError"

publishInferenceRequest :: Paths -> RuntimeMode -> Text.Text -> InferenceRequest -> IO Text.Text
publishInferenceRequest paths runtimeMode topic requestValue = do
  -- Phase 4 Sprint 4.13: this is the host-side @internal
  -- pulsar-roundtrip@ entrypoint; it never runs in a cluster pod, so
  -- 'discoverPulsarTransport' is invoked with no 'ClusterConfig' and
  -- falls through to the Apple-host publication-state discovery.
  maybeTransport <- discoverPulsarTransport paths runtimeMode Nothing
  requestIdValue <- generatePublishedRequestId
  let protoPayload =
        set (field @"requestId") requestIdValue $
          set (field @"requestModelId") (requestModelId requestValue) $
            set (field @"inputText") (inputText requestValue) $
              set (field @"inputObjectRef") (fromMaybe "" (inputObjectRef requestValue)) $
                set (field @"userId") (fromMaybe "" (requestUserId requestValue)) $
                  set (field @"contextId") (fromMaybe "" (requestContextId requestValue)) $
                    set (field @"runtimeMode") (runtimeModeId runtimeMode) defMessage
  case maybeTransport of
    Nothing -> do
      createDirectoryIfMissing True (topicDirectoryPath paths topic)
      let outputPath = topicDirectoryPath paths topic </> Text.unpack requestIdValue <.> "pb"
      writeInferenceRequestFile outputPath protoPayload
      pure requestIdValue
    Just transport -> do
      -- Direct/internal requests carry no durable prompt MessageId, so their
      -- broker dedup tuple must be scoped by the generated request id. A stable
      -- producer name would make later hash-derived sequence ids disappear
      -- behind Pulsar's highest-sequence-per-producer cursor.
      let options =
            inferenceRequestPublishOptions
              ("infernix-demo-publisher-" <> runtimeModeId runtimeMode)
              protoPayload
      publishTopicPayload transport topic options requestIdValue (encodeMessage protoPayload)
      pure requestIdValue

-- | Phase 7 Sprint 7.14 wiring for the demo WebSocket frontend:
-- browser-originated durable-context messages publish onto the same
-- Pulsar topic families consumed by the coordinator loops. This
-- keeps the WebSocket pod stateless: after JWT validation it only
-- translates client frames into typed JSON events and lets Pulsar
-- own ordering, compaction, and Failover handoff.
publishDemoClientMessage ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Contracts.UserId ->
  Contracts.WsClientMessage ->
  IO ()
publishDemoClientMessage paths runtimeMode maybeClusterConfig userIdValue clientMessage = do
  validateDemoClientMessage paths maybeClusterConfig clientMessage
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "demo WebSocket Pulsar dispatch is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport ->
      forM_
        (planDemoClientMessagePublications ConversationTopic.defaultDemoTopicNamespace userIdValue clientMessage)
        (publishDemoClientMessagePublication transport)

validateDemoClientMessage :: Paths -> Maybe ClusterConfig -> Contracts.WsClientMessage -> IO ()
validateDemoClientMessage paths maybeClusterConfig clientMessage =
  case clientMessage of
    Contracts.ClientCreateContext {} -> do
      demoConfig <- decodeDemoConfigFile (demoClientMessageDemoConfigPath paths maybeClusterConfig)
      case validateDemoClientMessageCatalog (models demoConfig) clientMessage of
        Right () -> pure ()
        Left validationError -> throwIO validationError
    _ -> pure ()

demoClientMessageDemoConfigPath :: Paths -> Maybe ClusterConfig -> FilePath
demoClientMessageDemoConfigPath paths maybeClusterConfig =
  case maybeClusterConfig of
    Just clusterConfig ->
      let demoPath = Text.unpack (demoConfigFilePath (clusterDemoBackend clusterConfig))
       in if null demoPath then Infernix.Config.generatedDemoConfigPath paths else demoPath
    Nothing -> Infernix.Config.generatedDemoConfigPath paths

-- | Stream per-user compacted metadata after the browser sends
-- 'Contracts.ClientHello'. Context and draft topics are independent, so
-- each owns its own session-local reader cursor and in-memory projection.
streamDemoUserMetadata ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Contracts.UserId ->
  (Contracts.WsServerMessage -> IO ()) ->
  IO ()
streamDemoUserMetadata paths runtimeMode maybeClusterConfig userIdValue sendMessage = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "demo WebSocket user metadata streaming is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport ->
      streamUserMetadataViaPulsar
        transport
        ConversationTopic.defaultDemoTopicNamespace
        userIdValue
        sendMessage

streamUserMetadataViaPulsar ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  (Contracts.WsServerMessage -> IO ()) ->
  IO ()
streamUserMetadataViaPulsar transport namespace userIdValue sendMessage = do
  sendMessage (Contracts.ServerContextListSnapshot (contextListStateFromMap Map.empty))
  sendMessage (Contracts.ServerDraftMapSnapshot (draftMapStateFromMap Map.empty))
  contextThread <-
    forkIO
      (streamUserContextListViaPulsar transport namespace userIdValue sendMessage)
  draftThread <-
    forkIO
      (streamUserDraftMapViaPulsar transport namespace userIdValue sendMessage)
  forever (threadDelay 60_000_000)
    `finally` do
      killThread contextThread
      killThread draftThread

retryBrowserStream :: Text.Text -> IO () -> IO ()
retryBrowserStream label action = go
  where
    go = do
      sessionResult <- try @SomeException action
      case sessionResult of
        Right _ -> do
          threadDelay 1_000_000
          go
        Left err
          | isAsyncException err -> throwIO err
          | isWebSocketConnectionClosed err -> pure ()
          | otherwise -> do
              hPutStrLn
                stderr
                ( Text.unpack label
                    <> " failed:\n"
                    <> displayException err
                )
              threadDelay 1_000_000
              go

isWebSocketConnectionClosed :: SomeException -> Bool
isWebSocketConnectionClosed err =
  case fromException err of
    Just WebSockets.ConnectionClosed -> True
    _ -> False

isAsyncException :: SomeException -> Bool
isAsyncException err =
  isJust (fromException err :: Maybe SomeAsyncException)

retryCoordinatorStream :: PulsarTransport -> Text.Text -> Text.Text -> IO () -> IO ()
retryCoordinatorStream transport topicValue label action = go
  where
    go = do
      sessionResult <- try @SomeException action
      case sessionResult of
        Right _ -> do
          threadDelay 1_000_000
          go
        Left err
          | isAsyncException err -> throwIO err
          | isTopicDeletionClose err -> do
              hPutStrLn
                stderr
                ( Text.unpack label
                    <> " stopped after topic close:\n"
                    <> displayException err
                )
          | isIdleTimeoutClose err -> do
              stillExists <- topicExistsAfterClose transport topicValue
              if stillExists
                then do
                  hPutStrLn
                    stderr
                    ( Text.unpack label
                        <> " failed:\n"
                        <> displayException err
                    )
                  threadDelay 1_000_000
                  go
                else
                  hPutStrLn
                    stderr
                    ( Text.unpack label
                        <> " stopped after deleted topic idle close:\n"
                        <> displayException err
                    )
          | otherwise -> do
              hPutStrLn
                stderr
                ( Text.unpack label
                    <> " failed:\n"
                    <> displayException err
                )
              threadDelay 1_000_000
              go

isTopicDeletionClose :: SomeException -> Bool
isTopicDeletionClose err =
  case fromException err of
    Just WebSockets.ConnectionClosed -> True
    Just (WebSockets.CloseRequest _ reason) ->
      not ("Idle timeout expired" `Text.isInfixOf` TextEncoding.decodeUtf8 (Lazy.toStrict reason))
    _ -> False

isIdleTimeoutClose :: SomeException -> Bool
isIdleTimeoutClose err =
  case fromException err of
    Just (WebSockets.CloseRequest _ reason) ->
      "Idle timeout expired" `Text.isInfixOf` TextEncoding.decodeUtf8 (Lazy.toStrict reason)
    _ -> False

topicExistsAfterClose :: PulsarTransport -> Text.Text -> IO Bool
topicExistsAfterClose transport topicValue = do
  result <- try @SomeException $ do
    adminBaseUrl <- requirePulsarAdminBaseUrl transport
    topicRef <- requireTopicRef topicValue
    manager <- newManager defaultManagerSettings
    topics <-
      listNamespaceTopics
        manager
        adminBaseUrl
        ( ConversationTopic.TopicNamespace
            (topicTenant topicRef)
            (topicNamespace topicRef)
        )
    pure (topicValue `elem` topics)
  case result of
    Right exists -> pure exists
    Left _ -> pure True

streamUserContextListViaPulsar ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  (Contracts.WsServerMessage -> IO ()) ->
  IO ()
streamUserContextListViaPulsar transport namespace userIdValue sendMessage = do
  let contextsTopic =
        ConversationTopic.contextsMetadataTopicName namespace userIdValue
      readerName =
        "browser-context-list-"
          <> sanitizeTopic (Contracts.unUserId userIdValue)
  stateRef <- newIORef Map.empty
  topicRef <- requireTopicRef contextsTopic
  let readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  retryBrowserStream ("browser context-list stream for " <> contextsTopic) $
    runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
      forever
        (handleContextMetadataStreamMessage stateRef sendMessage connection)

handleContextMetadataStreamMessage ::
  IORef (Map Contracts.ContextId Contracts.ContextSummary) ->
  (Contracts.WsServerMessage -> IO ()) ->
  WebSockets.Connection ->
  IO ()
handleContextMetadataStreamMessage stateRef sendMessage connection = do
  rawEnvelope <- receiveJsonFrame "Pulsar browser context metadata stream message" connection
  envelope <- decodeJsonText "Pulsar browser context metadata stream message" rawEnvelope
  eventBytes <- conversationPayloadBytes envelope
  case eitherDecode (Lazy.fromStrict eventBytes) of
    Left decodeError ->
      hPutStrLn
        stderr
        ( "browser context-list stream skipping undecodable context metadata event "
            <> Text.unpack (envelopeMessageId envelope)
            <> ": "
            <> decodeError
        )
    Right contextEvent -> do
      patch <- atomicModifyIORef' stateRef $ \state ->
        let (nextState, nextPatch) = applyContextMetadataPatch state contextEvent
         in (nextState, nextPatch)
      sendMessage (Contracts.ServerContextListPatch patch)
  sendAck connection (envelopeMessageId envelope)

applyContextMetadataPatch ::
  Map Contracts.ContextId Contracts.ContextSummary ->
  Contracts.ContextMetadataEvent ->
  (Map Contracts.ContextId Contracts.ContextSummary, Contracts.ContextListPatch)
applyContextMetadataPatch state event =
  let summary = contextSummaryForEvent state event
      nextState = Map.insert (Contracts.contextSummaryId summary) summary state
   in (nextState, Contracts.ContextListUpsert summary)

contextSummaryForEvent ::
  Map Contracts.ContextId Contracts.ContextSummary ->
  Contracts.ContextMetadataEvent ->
  Contracts.ContextSummary
contextSummaryForEvent state event =
  case event of
    Contracts.ContextCreated contextIdValue modelId title ->
      Contracts.ContextSummary
        { Contracts.contextSummaryId = contextIdValue,
          Contracts.contextSummaryModelId = modelId,
          Contracts.contextSummaryTitle = title,
          Contracts.contextSummarySoftDeleted = False
        }
    Contracts.ContextRenamed contextIdValue title ->
      case Map.lookup contextIdValue state of
        Just existing ->
          Contracts.ContextSummary
            { Contracts.contextSummaryId = Contracts.contextSummaryId existing,
              Contracts.contextSummaryModelId = Contracts.contextSummaryModelId existing,
              Contracts.contextSummaryTitle = title,
              Contracts.contextSummarySoftDeleted = Contracts.contextSummarySoftDeleted existing
            }
        Nothing ->
          Contracts.ContextSummary
            { Contracts.contextSummaryId = contextIdValue,
              Contracts.contextSummaryModelId = "",
              Contracts.contextSummaryTitle = title,
              Contracts.contextSummarySoftDeleted = False
            }
    Contracts.ContextSoftDeleted contextIdValue ->
      case Map.lookup contextIdValue state of
        Just existing ->
          Contracts.ContextSummary
            { Contracts.contextSummaryId = Contracts.contextSummaryId existing,
              Contracts.contextSummaryModelId = Contracts.contextSummaryModelId existing,
              Contracts.contextSummaryTitle = Contracts.contextSummaryTitle existing,
              Contracts.contextSummarySoftDeleted = True
            }
        Nothing ->
          Contracts.ContextSummary
            { Contracts.contextSummaryId = contextIdValue,
              Contracts.contextSummaryModelId = "",
              Contracts.contextSummaryTitle = "",
              Contracts.contextSummarySoftDeleted = True
            }

contextListStateFromMap :: Map Contracts.ContextId Contracts.ContextSummary -> Contracts.ContextListState
contextListStateFromMap state =
  Contracts.ContextListState
    { Contracts.contextListStateContexts = Map.elems state
    }

streamUserDraftMapViaPulsar ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  (Contracts.WsServerMessage -> IO ()) ->
  IO ()
streamUserDraftMapViaPulsar transport namespace userIdValue sendMessage = do
  let draftsTopic =
        ConversationTopic.draftsMetadataTopicName namespace userIdValue
      readerName =
        "browser-draft-map-"
          <> sanitizeTopic (Contracts.unUserId userIdValue)
  stateRef <- newIORef Map.empty
  topicRef <- requireTopicRef draftsTopic
  let readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  retryBrowserStream ("browser draft-map stream for " <> draftsTopic) $
    runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
      forever
        (handleDraftMetadataStreamMessage stateRef sendMessage connection)

handleDraftMetadataStreamMessage ::
  IORef (Map Text.Text Text.Text) ->
  (Contracts.WsServerMessage -> IO ()) ->
  WebSockets.Connection ->
  IO ()
handleDraftMetadataStreamMessage stateRef sendMessage connection = do
  rawEnvelope <- receiveJsonFrame "Pulsar browser draft metadata stream message" connection
  envelope <- decodeJsonText "Pulsar browser draft metadata stream message" rawEnvelope
  eventBytes <- conversationPayloadBytes envelope
  case eitherDecode (Lazy.fromStrict eventBytes) of
    Left decodeError ->
      hPutStrLn
        stderr
        ( "browser draft-map stream skipping undecodable draft event "
            <> Text.unpack (envelopeMessageId envelope)
            <> ": "
            <> decodeError
        )
    Right draftEvent -> do
      patch <- atomicModifyIORef' stateRef $ \state ->
        let (nextState, nextPatch) = applyDraftMetadataPatch state draftEvent
         in (nextState, nextPatch)
      sendMessage (Contracts.ServerDraftMapPatch patch)
  sendAck connection (envelopeMessageId envelope)

applyDraftMetadataPatch ::
  Map Text.Text Text.Text ->
  Contracts.DraftEvent ->
  (Map Text.Text Text.Text, Contracts.DraftMapPatch)
applyDraftMetadataPatch state event =
  case event of
    Contracts.DraftUpdated contextIdValue textValue ->
      let key = Contracts.unContextId contextIdValue
          entry = Contracts.DraftEntry contextIdValue textValue
       in (Map.insert key textValue state, Contracts.DraftMapUpsert entry)
    Contracts.DraftCleared contextIdValue ->
      let key = Contracts.unContextId contextIdValue
       in (Map.delete key state, Contracts.DraftMapRemove contextIdValue)

draftMapStateFromMap :: Map Text.Text Text.Text -> Contracts.DraftMapState
draftMapStateFromMap state =
  Contracts.DraftMapState
    { Contracts.draftMapStateDrafts =
        [ Contracts.DraftEntry (Contracts.ContextId key) textValue
        | (key, textValue) <- Map.toAscList state
        ]
    }

-- | Stream the canonical broker view for one browser-selected context.
-- The WebSocket pod remains stateless: it owns only this session-local
-- reader cursor and reducer cache, while Pulsar remains the source of
-- truth for the append-only conversation log.
streamDemoContextConversation ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Contracts.UserId ->
  Contracts.ContextId ->
  (Contracts.WsServerMessage -> IO ()) ->
  IO ()
streamDemoContextConversation paths runtimeMode maybeClusterConfig userIdValue contextIdValue sendMessage = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "demo WebSocket context streaming is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport ->
      streamContextConversationViaPulsar
        transport
        ConversationTopic.defaultDemoTopicNamespace
        userIdValue
        contextIdValue
        sendMessage

streamContextConversationViaPulsar ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  Contracts.ContextId ->
  (Contracts.WsServerMessage -> IO ()) ->
  IO ()
streamContextConversationViaPulsar transport namespace userIdValue contextIdValue sendMessage = do
  let conversationTopic =
        ConversationTopic.conversationTopicName namespace userIdValue contextIdValue
      initialSnapshot =
        Contracts.ConversationState
          { Contracts.conversationStateContextId = contextIdValue,
            Contracts.conversationStateMessages = [],
            Contracts.conversationStatePrefixHash = ""
          }
      readerName =
        "browser-context-"
          <> sanitizeTopic
            ( Contracts.unUserId userIdValue
                <> "-"
                <> Contracts.unContextId contextIdValue
            )
  sendMessage (Contracts.ServerConversationSnapshot initialSnapshot)
  reducerStateRef <- newIORef (initialReducerState contextIdValue)
  seenMessageIdsRef <- newIORef Set.empty
  topicRef <- requireTopicRef conversationTopic
  let readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  retryBrowserStream ("browser context stream for " <> conversationTopic) $
    runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
      forever
        ( handleConversationStreamMessage
            contextIdValue
            reducerStateRef
            seenMessageIdsRef
            sendMessage
            connection
        )

handleConversationStreamMessage ::
  Contracts.ContextId ->
  IORef ReducerState ->
  IORef (Set Contracts.MessageId) ->
  (Contracts.WsServerMessage -> IO ()) ->
  WebSockets.Connection ->
  IO ()
handleConversationStreamMessage contextIdValue reducerStateRef seenMessageIdsRef sendMessage connection = do
  rawEnvelope <- receiveJsonFrame "Pulsar browser conversation stream message" connection
  envelope <- decodeJsonText "Pulsar browser conversation stream message" rawEnvelope
  let messageId = Contracts.MessageId (envelopeMessageId envelope)
  alreadySeen <-
    atomicModifyIORef' seenMessageIdsRef $ \seen ->
      if Set.member messageId seen
        then (seen, True)
        else (Set.insert messageId seen, False)
  unless alreadySeen $ do
    eventBytes <- conversationPayloadBytes envelope
    case eitherDecode (Lazy.fromStrict eventBytes) of
      Left decodeError ->
        hPutStrLn
          stderr
          ( "browser context stream skipping undecodable conversation event "
              <> Text.unpack (envelopeMessageId envelope)
              <> ": "
              <> decodeError
          )
      Right conversationEvent -> do
        let conversationMessage =
              Contracts.ConversationMessage messageId conversationEvent
        maybePatch <- atomicModifyIORef' reducerStateRef $ \state ->
          case stepReducer state conversationMessage of
            StepAdvanced advanced patch -> (advanced, Just patch)
            StepDropped unchanged -> (unchanged, Nothing)
        forM_ maybePatch $ \patch ->
          sendMessage
            ( Contracts.ServerConversationPatch
                contextIdValue
                patch
            )
  sendAck connection (envelopeMessageId envelope)

data DemoClientMessagePublication = DemoClientMessagePublication
  { demoClientPublicationTopic :: Text.Text,
    demoClientPublicationProducerName :: Text.Text,
    demoClientPublicationMessageKey :: Maybe Text.Text,
    demoClientPublicationSequenceKey :: Text.Text,
    demoClientPublicationPayload :: Lazy.ByteString
  }
  deriving (Eq, Show)

data DemoClientMessageError = DemoClientMessageError
  { demoClientMessageErrorCode :: Text.Text,
    demoClientMessageErrorMessage :: Text.Text
  }
  deriving (Eq, Show)

instance Exception DemoClientMessageError

validateDemoClientMessageCatalog :: [ModelDescriptor] -> Contracts.WsClientMessage -> Either DemoClientMessageError ()
validateDemoClientMessageCatalog catalog clientMessage =
  case clientMessage of
    Contracts.ClientCreateContext _ modelIdValue _ ->
      if modelIdValue `Set.member` activeModelIds
        then Right ()
        else
          Left
            DemoClientMessageError
              { demoClientMessageErrorCode = "unknown-model",
                demoClientMessageErrorMessage =
                  "modelId " <> modelIdValue <> " is not in the active catalog"
              }
    _ -> Right ()
  where
    activeModelIds = Set.fromList (map modelId catalog)

planDemoClientMessagePublications ::
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  Contracts.WsClientMessage ->
  [DemoClientMessagePublication]
planDemoClientMessagePublications namespace userIdValue clientMessage =
  case clientMessage of
    Contracts.ClientHello _ ->
      []
    Contracts.ClientSubscribeContext _ ->
      []
    Contracts.ClientSubmitPrompt contextIdValue payload ->
      [ conversationPublication
          namespace
          userIdValue
          contextIdValue
          (Contracts.unClientIdempotencyKey (Contracts.promptClientIdempotencyKey payload))
          (Contracts.ConversationUserPromptEvent payload)
      ]
    Contracts.ClientCancelPrompt contextIdValue promptMessageId ->
      [ conversationPublication
          namespace
          userIdValue
          contextIdValue
          (Contracts.unMessageId promptMessageId)
          (Contracts.ConversationCancelEvent (Contracts.ConversationCancelPayload promptMessageId))
      ]
    Contracts.ClientRecordUpload contextIdValue payload ->
      [ conversationPublication
          namespace
          userIdValue
          contextIdValue
          (uploadEventSequenceKey payload)
          (Contracts.ConversationUserUploadEvent payload)
      ]
    Contracts.ClientUpdateDraft contextIdValue draftText ->
      [ compactedUserPublication
          (ConversationTopic.draftsMetadataTopicName namespace userIdValue)
          "frontend-drafts"
          userIdValue
          (Contracts.unContextId contextIdValue)
          (draftEventSequenceKey contextIdValue draftText)
          ( if Text.null draftText
              then Contracts.DraftCleared contextIdValue
              else Contracts.DraftUpdated contextIdValue draftText
          )
      ]
    Contracts.ClientCreateContext contextIdValue modelId title ->
      [ contextMetadataPublication
          namespace
          userIdValue
          contextIdValue
          (Contracts.unContextId contextIdValue <> ":create:" <> modelId <> ":" <> title)
          (Contracts.ContextCreated contextIdValue modelId title)
      ]
    Contracts.ClientRenameContext contextIdValue title ->
      [ contextMetadataPublication
          namespace
          userIdValue
          contextIdValue
          (Contracts.unContextId contextIdValue <> ":rename:" <> title)
          (Contracts.ContextRenamed contextIdValue title)
      ]
    Contracts.ClientSoftDeleteContext contextIdValue ->
      [ contextMetadataPublication
          namespace
          userIdValue
          contextIdValue
          (Contracts.unContextId contextIdValue <> ":soft-delete")
          (Contracts.ContextSoftDeleted contextIdValue)
      ]

uploadEventSequenceKey :: Contracts.ConversationUserUploadPayload -> Text.Text
uploadEventSequenceKey payload =
  let ref = Contracts.uploadObjectRef payload
   in "upload:" <> Contracts.objectBucket ref <> ":" <> Contracts.objectKey ref

draftEventSequenceKey :: Contracts.ContextId -> Text.Text -> Text.Text
draftEventSequenceKey contextIdValue draftText
  | Text.null draftText = Contracts.unContextId contextIdValue <> ":clear"
  | otherwise = Contracts.unContextId contextIdValue <> ":" <> draftText

conversationPublication ::
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  Contracts.ContextId ->
  Text.Text ->
  Contracts.ConversationEvent ->
  DemoClientMessagePublication
conversationPublication namespace userIdValue contextIdValue sequenceKey event =
  let Contracts.UserId userIdText = userIdValue
      Contracts.ContextId contextIdText = contextIdValue
   in DemoClientMessagePublication
        { demoClientPublicationTopic =
            ConversationTopic.conversationTopicName namespace userIdValue contextIdValue,
          demoClientPublicationProducerName =
            dedupProducerName
              ("frontend-conversation-" <> userIdText <> "-" <> contextIdText)
              sequenceKey,
          demoClientPublicationMessageKey = Nothing,
          demoClientPublicationSequenceKey = sequenceKey,
          demoClientPublicationPayload = encode event
        }

contextMetadataPublication ::
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  Contracts.ContextId ->
  Text.Text ->
  Contracts.ContextMetadataEvent ->
  DemoClientMessagePublication
contextMetadataPublication namespace userIdValue contextIdValue sequenceKey event =
  let Contracts.ContextId contextIdText = contextIdValue
   in compactedUserPublication
        (ConversationTopic.contextsMetadataTopicName namespace userIdValue)
        "frontend-contexts"
        userIdValue
        contextIdText
        sequenceKey
        event

compactedUserPublication ::
  (ToJSON event) =>
  Text.Text ->
  Text.Text ->
  Contracts.UserId ->
  Text.Text ->
  Text.Text ->
  event ->
  DemoClientMessagePublication
compactedUserPublication topicValue producerPrefix (Contracts.UserId userIdText) messageKey sequenceKey event =
  DemoClientMessagePublication
    { demoClientPublicationTopic = topicValue,
      demoClientPublicationProducerName =
        dedupProducerName
          (producerPrefix <> "-" <> userIdText)
          sequenceKey,
      demoClientPublicationMessageKey = Just messageKey,
      demoClientPublicationSequenceKey = sequenceKey,
      demoClientPublicationPayload = encode event
    }

dedupProducerName :: Text.Text -> Text.Text -> Text.Text
dedupProducerName producerScope sequenceKey =
  producerScope <> "-" <> Text.pack (show (stableSequenceId sequenceKey))

publishDemoClientMessagePublication ::
  PulsarTransport ->
  DemoClientMessagePublication ->
  IO ()
publishDemoClientMessagePublication transport publication =
  publishTopicPayload
    transport
    (demoClientPublicationTopic publication)
    ( (defaultPublishOptions (demoClientPublicationProducerName publication))
        { publishMessageKey = demoClientPublicationMessageKey publication,
          publishSequenceId =
            Just (stableSequenceId (demoClientPublicationSequenceKey publication))
        }
    )
    (demoClientPublicationSequenceKey publication)
    (Lazy.toStrict (demoClientPublicationPayload publication))

stableSequenceId :: Text.Text -> Integer
stableSequenceId value =
  ByteString.foldl' step 0 (ByteString.take 8 (SHA256.hash (TextEncoding.encodeUtf8 value)))
    -- Pulsar WebSocket producer URLs parse @initialSequenceId@ as a signed Java long.
    `mod` 9223372036854775807
  where
    step acc byte = acc * 256 + fromIntegral byte

publishRawTopicPayload ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Text.Text ->
  Text.Text ->
  Maybe Text.Text ->
  Text.Text ->
  ByteString.ByteString ->
  IO ()
publishRawTopicPayload paths runtimeMode maybeClusterConfig topic producerName messageKey contextValue payload = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "Pulsar publish is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport ->
      publishTopicPayload
        transport
        topic
        ((defaultPublishOptions producerName) {publishMessageKey = messageKey})
        contextValue
        payload

publishModelBootstrapRequest ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  BootstrapModels.ModelBootstrapRequest ->
  IO ()
publishModelBootstrapRequest paths runtimeMode maybeClusterConfig request = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "model-bootstrap publish is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport -> publishModelBootstrapRequestViaTransport transport request

publishModelBootstrapRequestViaTransport ::
  PulsarTransport ->
  BootstrapModels.ModelBootstrapRequest ->
  IO ()
publishModelBootstrapRequestViaTransport transport request = do
  let systemNamespace = ConversationTopic.systemTopicNamespace
      requestTopic = ConversationTopic.modelBootstrapRequestTopicName systemNamespace
      dedupKey = BootstrapModels.bootstrapRequestDedupKey request
      options =
        (defaultPublishOptions ("infernix-engine-model-bootstrap-" <> dedupKey))
          { publishMessageKey = Just (BootstrapModels.bootstrapRequestModelId request),
            publishSequenceId = Just (stableSequenceId dedupKey)
          }
  publishTopicPayload
    transport
    requestTopic
    options
    dedupKey
    (Lazy.toStrict (encode request))

readRawTopicPayloads ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Text.Text ->
  Int ->
  IO [RawTopicMessage]
readRawTopicPayloads paths runtimeMode maybeClusterConfig topic maxMessages
  | maxMessages <= 0 = pure []
  | otherwise = do
      maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
      case maybeTransport of
        Nothing ->
          ioError
            ( userError
                ( "Pulsar read is unavailable for "
                    <> Text.unpack (runtimeModeId runtimeMode)
                    <> "; no Pulsar transport could be discovered"
                )
            )
        Just transport ->
          readRawTopicPayloadsViaPulsar transport topic maxMessages

readNamespaceCompactionThreshold ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Text.Text ->
  IO Int
readNamespaceCompactionThreshold paths runtimeMode maybeClusterConfig namespaceValue = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "Pulsar namespace compaction threshold read is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport ->
      readNamespaceCompactionThresholdViaPulsar transport namespaceValue

compactTopicAndWait ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Text.Text ->
  IO ()
compactTopicAndWait paths runtimeMode maybeClusterConfig topic = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "Pulsar topic compaction is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport -> do
      triggerTopicCompactionViaPulsar transport topic
      waitForTopicCompactionCompleteViaPulsar transport topic

deleteDemoUserTopics ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Contracts.UserId ->
  IO Int
deleteDemoUserTopics paths runtimeMode maybeClusterConfig userIdValue = do
  result <- deleteDemoUserTopicsWithAttemptBudget paths runtimeMode maybeClusterConfig userIdValue 240
  case demoUserTopicDeletionRemaining result of
    [] -> pure (demoUserTopicDeletionDeleted result)
    remainingTopics ->
      let Contracts.UserId userIdText = userIdValue
       in ioError
            ( userError
                ( "failed to delete Pulsar demo topics for user "
                    <> Text.unpack userIdText
                    <> "; topics still present after retries: "
                    <> Text.unpack (Text.intercalate ", " remainingTopics)
                )
            )

deleteDemoUserTopicsWithAttemptBudget ::
  Paths ->
  RuntimeMode ->
  Maybe ClusterConfig ->
  Contracts.UserId ->
  Int ->
  IO DemoUserTopicDeletion
deleteDemoUserTopicsWithAttemptBudget paths runtimeMode maybeClusterConfig userIdValue maxAttempts = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  case maybeTransport of
    Nothing ->
      ioError
        ( userError
            ( "Pulsar account cleanup is unavailable for "
                <> Text.unpack (runtimeModeId runtimeMode)
                <> "; no Pulsar transport could be discovered"
            )
        )
    Just transport ->
      deleteDemoUserTopicsViaPulsarWithAttemptBudget
        transport
        ConversationTopic.defaultDemoTopicNamespace
        userIdValue
        maxAttempts

deleteDemoUserTopicsViaPulsarWithAttemptBudget ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  Int ->
  IO DemoUserTopicDeletion
deleteDemoUserTopicsViaPulsarWithAttemptBudget transport namespaceValue userIdValue maxAttempts = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  manager <- newManager defaultManagerSettings
  verifyDeleted manager adminBaseUrl 1 0 Set.empty
  where
    requiredEmptyChecks = 5 :: Int
    retryDelayMicros = 250_000

    verifyDeleted manager adminBaseUrl attempt emptyChecks deletedTopics = do
      topics <- listNamespaceTopics manager adminBaseUrl namespaceValue
      let userTopics =
            filter
              (ConversationTopic.topicBelongsToUser namespaceValue userIdValue)
              topics
      if null userTopics
        then
          if emptyChecks + 1 >= requiredEmptyChecks
            then
              pure
                DemoUserTopicDeletion
                  { demoUserTopicDeletionDeleted = Set.size deletedTopics,
                    demoUserTopicDeletionRemaining = []
                  }
            else do
              threadDelay retryDelayMicros
              verifyDeleted manager adminBaseUrl (attempt + 1) (emptyChecks + 1) deletedTopics
        else do
          forM_ userTopics (deleteTopicViaPulsar manager adminBaseUrl)
          let nextDeletedTopics = deletedTopics <> Set.fromList userTopics
          if attempt >= maxAttempts
            then
              pure
                DemoUserTopicDeletion
                  { demoUserTopicDeletionDeleted = Set.size nextDeletedTopics,
                    demoUserTopicDeletionRemaining = userTopics
                  }
            else do
              threadDelay retryDelayMicros
              verifyDeleted manager adminBaseUrl (attempt + 1) 0 nextDeletedTopics

readRawTopicPayloadsViaPulsar :: PulsarTransport -> Text.Text -> Int -> IO [RawTopicMessage]
readRawTopicPayloadsViaPulsar transport topic maxMessages = do
  topicRef <- requireTopicRef topic
  let readerName =
        "infernix-read-"
          <> sanitizeTopic topic
          <> "-"
          <> show maxMessages
      readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
    go connection maxMessages []
  where
    go _connection remaining acc
      | remaining <= 0 = pure (reverse acc)
    go connection remaining acc = do
      maybeRawEnvelope <- timeout 5000000 (receiveJsonFrame "Pulsar raw reader message" connection)
      case maybeRawEnvelope of
        Nothing -> pure (reverse acc)
        Just rawEnvelope -> do
          envelope <- decodeJsonText "Pulsar raw reader message" rawEnvelope
          sendAck connection (envelopeMessageId envelope)
          decoded <- decodeRawTopicMessage envelope
          go connection (remaining - 1) (decoded : acc)

decodeRawTopicMessage :: PulsarEnvelope -> IO RawTopicMessage
decodeRawTopicMessage envelope = do
  payloadBytes <- decodeEnvelopeBase64Payload "raw topic" envelope
  pure
    RawTopicMessage
      { rawTopicMessageId = envelopeMessageId envelope,
        rawTopicMessageKey = envelopeKey envelope,
        rawTopicMessagePayload = payloadBytes
      }

decodeEnvelopeBase64Payload :: String -> PulsarEnvelope -> IO ByteString.ByteString
decodeEnvelopeBase64Payload payloadLabel envelope =
  case Base64.decode (TextEncoding.encodeUtf8 (envelopePayload envelope)) of
    Right raw -> pure raw
    Left err ->
      ioError
        ( userError
            ( "failed to decode base64 "
                <> payloadLabel
                <> " payload for message "
                <> Text.unpack (envelopeMessageId envelope)
                <> ":\n"
                <> err
            )
        )

readPublishedInferenceResultMaybe :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
readPublishedInferenceResultMaybe paths runtimeMode topic requestIdValue = do
  -- Phase 4 Sprint 4.13: see note on 'publishInferenceRequest' above.
  maybeTransport <- discoverPulsarTransport paths runtimeMode Nothing
  case maybeTransport of
    Nothing -> do
      let outputPath = topicDirectoryPath paths topic </> Text.unpack requestIdValue <.> "pb"
      exists <- doesFileExist outputPath
      if not exists
        then pure Nothing
        else do
          encoded <- readFileBytes outputPath
          case decodeMessage encoded of
            Left err ->
              ioError (userError ("failed to decode inference result from " <> outputPath <> ": " <> err))
            Right protoResult ->
              pure (protoResultToDomain protoResult)
    Just transport ->
      readPublishedInferenceResultViaPulsar transport topic requestIdValue

drainTopic :: Paths -> RuntimeMode -> EngineCommandOverrideMap -> DaemonConfig -> DemoConfig -> Text.Text -> IO ()
drainTopic paths runtimeMode overrides daemonConfig demoConfig =
  drainTopicWithKVCache paths runtimeMode overrides daemonConfig demoConfig Nothing

drainTopicWithKVCache :: Paths -> RuntimeMode -> EngineCommandOverrideMap -> DaemonConfig -> DemoConfig -> Maybe KVCache.EngineKVCache -> Text.Text -> IO ()
drainTopicWithKVCache paths runtimeMode overrides daemonConfig demoConfig maybeEngineKVCache requestTopicValue =
  case daemonConfigRole daemonConfig of
    Coordinator ->
      forwardTopicToDerivedPool paths runtimeMode demoConfig requestTopicValue
    Engine ->
      drainInferenceTopic paths runtimeMode overrides maybeEngineKVCache (daemonConfigResultTopic daemonConfig) requestTopicValue
    Webapp ->
      ioError (userError "webapp role does not drain inference topics")

forwardTopicToDerivedPool :: Paths -> RuntimeMode -> DemoConfig -> Text.Text -> IO ()
forwardTopicToDerivedPool paths runtimeMode demoConfig sourceTopicValue = do
  let sourceDirectory = topicDirectoryPath paths sourceTopicValue
  sourceDirectoryPresent <- doesDirectoryExist sourceDirectory
  unless sourceDirectoryPresent (createDirectoryIfMissing True sourceDirectory)
  requestFiles <- sort <$> listDirectory sourceDirectory
  forM_ (filter (".pb" `endsWith`) requestFiles) $ \requestFile -> do
    let sourcePath = sourceDirectory </> requestFile
    encodedRequest <- readFileBytes sourcePath
    decodedRequest <-
      case decodeMessage encodedRequest of
        Left err ->
          ioError (userError ("failed to decode inference request from " <> sourcePath <> ": " <> err))
        Right requestValue ->
          pure requestValue
    targetTopicValue <-
      case batchTopicForRequest runtimeMode demoConfig decodedRequest of
        Left err ->
          ioError (userError err)
        Right topicValue ->
          pure topicValue
    let targetDirectory = topicDirectoryPath paths targetTopicValue
        targetPath = targetDirectory </> requestFile
    createDirectoryIfMissing True targetDirectory
    ByteString.writeFile targetPath encodedRequest
    removeFile sourcePath

drainInferenceTopic :: Paths -> RuntimeMode -> EngineCommandOverrideMap -> Maybe KVCache.EngineKVCache -> Text.Text -> Text.Text -> IO ()
drainInferenceTopic paths runtimeMode overrides maybeEngineKVCache resultTopicValue requestTopicValue = do
  let requestDirectory = topicDirectoryPath paths requestTopicValue
  requestDirectoryPresent <- doesDirectoryExist requestDirectory
  unless requestDirectoryPresent (createDirectoryIfMissing True requestDirectory)
  requestFiles <- sort <$> listDirectory requestDirectory
  forM_ (filter (".pb" `endsWith`) requestFiles) $ \requestFile -> do
    let requestPath = requestDirectory </> requestFile
    encodedRequest <- readFileBytes requestPath
    case decodeMessage encodedRequest of
      Left err ->
        ioError (userError ("failed to decode inference request from " <> requestPath <> ": " <> err))
      Right protoRequest -> do
        publishedResult <- publishedResultFromRequest Nothing paths runtimeMode overrides maybeEngineKVCache protoRequest
        createDirectoryIfMissing True (topicDirectoryPath paths resultTopicValue)
        writeInferenceResultFile
          (topicDirectoryPath paths resultTopicValue </> Text.unpack (requestId publishedResult) <.> "pb")
          (domainResultToProto publishedResult)
        removeFile requestPath

ensureSchemaMarkers :: Paths -> DemoConfig -> IO ()
ensureSchemaMarkers paths demoConfig = do
  let topics = schemaTopicsForDemoConfig demoConfig
  forM_ topics writeSchemaMarker
  where
    writeSchemaMarker topicValue = do
      createDirectoryIfMissing True (topicDirectoryPath paths topicValue)
      createDirectoryIfMissing True (takeDirectory (schemaMarkerPath paths topicValue))
      writeFile
        (schemaMarkerPath paths topicValue)
        (unlines ["schema: protobuf", "topic: " <> Text.unpack topicValue])

serviceReadinessMarkerPath :: Paths -> FilePath
serviceReadinessMarkerPath paths =
  runtimeRoot paths </> "service" </> "subscription.ready"

clearServiceReadinessMarker :: Paths -> IO ()
clearServiceReadinessMarker paths = do
  let markerPath = serviceReadinessMarkerPath paths
  markerPresent <- doesFileExist markerPath
  when markerPresent (removeFile markerPath)

writeServiceReadinessMarker :: Paths -> IO ()
writeServiceReadinessMarker paths = do
  let markerPath = serviceReadinessMarkerPath paths
  createDirectoryIfMissing True (takeDirectory markerPath)
  writeFile markerPath "ready\n"

schemaMarkerPath :: Paths -> Text.Text -> FilePath
schemaMarkerPath paths topicValue =
  runtimeRoot paths </> "pulsar" </> "schemas" </> sanitizeTopic topicValue <.> "schema"

topicDirectoryPath :: Paths -> Text.Text -> FilePath
topicDirectoryPath paths topicValue =
  runtimeRoot paths </> "pulsar" </> "topics" </> sanitizeTopic topicValue

-- | Phase 4 Sprint 4.13: @INFERNIX_PULSAR_WS_BASE_URL@ and
-- @INFERNIX_PULSAR_ADMIN_URL@ env reads retired. Cluster-resident
-- pods now provide both endpoints through the mounted
-- 'ClusterConfig'; host-native flows fall back to the existing
-- Apple publication-state discovery path.
discoverPulsarTransport :: Paths -> RuntimeMode -> Maybe ClusterConfig -> IO (Maybe PulsarTransport)
discoverPulsarTransport paths runtimeMode maybeClusterConfig =
  case maybeClusterConfig of
    Just clusterConfig -> discoverPulsarTransportFromCluster clusterConfig fallback
    Nothing -> fallback
  where
    fallback = case (controlPlaneContext paths, runtimeMode) of
      (HostNative, AppleSilicon) -> discoverAppleHostPulsarTransport paths
      -- Phase 6 Sprint 6.28 follow-on (May 26, 2026): the Linux
      -- outer-container test path (`infernix internal
      -- pulsar-roundtrip`, integration `validateServiceRuntimeLoop`)
      -- runs inside the launcher container without a mounted
      -- @ClusterConfig@. The supported transport is the routed
      -- Pulsar edge: the launcher is attached to Kind's @kind@
      -- network via @ensureOuterContainerKindNetworkAccess@, so the
      -- published edge port (default 9090) routes
      -- @ws://127.0.0.1:<edgePort>/pulsar/ws/v2@ to the in-cluster
      -- Pulsar proxy. Without this, the test wrote to the
      -- filesystem-topic-spool fallback that the cluster daemon does
      -- not consume.
      (OuterContainer, _) ->
        case pathsHostConfig paths of
          Just hostConfig -> discoverOuterContainerPulsarTransport hostConfig runtimeMode
          Nothing -> pure Nothing
      _ -> pure Nothing

-- | Phase 6 Sprint 6.28 follow-on (May 26, 2026): outer-container
-- Pulsar transport discovery via the kind control-plane's IPv4. The
-- launcher cannot use @127.0.0.1:9090@ from inside its own network
-- namespace, and Kind's docker-DNS entry for @<cluster>-control-plane@
-- returns an IPv6 ULA address first (@fc00:f853:ccd:e793::/64@) that
-- Haskell's getAddrInfo+connect doesn't route on the kind bridge. The
-- supported flow asks Docker for the kind control-plane container's
-- IPv4 on the @kind@ network directly, then connects to that explicit
-- IPv4 — which the launcher reaches over the attached @kind@ bridge via
-- @ensureOuterContainerKindNetworkAccess@.
--
-- The launcher is a trusted local component (it created the cluster), so
-- like the Apple host-native path (@discoverAppleHostPulsarTransport@) it
-- talks to Pulsar's @/admin/v2@ and @/ws/v2@ surfaces through the
-- un-gated Pulsar-proxy HTTP NodePort (@pulsarProxyHttpNodePort@, 30080)
-- rather than the Keycloak-JWT-gated @/pulsar/admin@ Envoy edge route on
-- the gateway NodePort (30090). The operator-routes 'SecurityPolicy'
-- gates browser access to @/pulsar/admin@ only; routing trusted admin-v2
-- reconcile/compaction calls through the edge would (and did) fail with
-- @401 Jwt is missing@, while @/pulsar/ws@ — never in that policy —
-- happened to work. Reaching the proxy NodePort directly keeps both
-- halves un-gated and consistent with the Apple lane.
discoverOuterContainerPulsarTransport :: HostConfig.HostConfig -> RuntimeMode -> IO (Maybe PulsarTransport)
discoverOuterContainerPulsarTransport hostConfig runtimeMode = do
  let containerName =
        "infernix-" <> Text.unpack (runtimeModeId runtimeMode) <> "-control-plane"
      dockerPath = Text.unpack (HostConfig.hostDocker (HostConfig.hostToolPaths hostConfig))
      dockerArgs =
        [ "inspect",
          containerName,
          "--format",
          "{{.NetworkSettings.Networks.kind.IPAddress}}"
        ]
  ipResult <- try (readProcessWithExitCode dockerPath dockerArgs "") :: IO (Either SomeException (ExitCode, String, String))
  pure (buildOuterContainerTransport ipResult)

buildOuterContainerTransport ::
  Either SomeException (ExitCode, String, String) -> Maybe PulsarTransport
buildOuterContainerTransport ipResult =
  case ipResult of
    Right (ExitSuccess, rawOutput, _) ->
      let ipv4 = filter (/= '\n') (trimWhitespacePulsar rawOutput)
       in if null ipv4
            then Nothing
            else buildOuterContainerTransportFromIpv4 ipv4
    _ -> Nothing

buildOuterContainerTransportFromIpv4 :: String -> Maybe PulsarTransport
buildOuterContainerTransportFromIpv4 ipv4 =
  fmap (transportFromBase adminUrl) (eitherToMaybe (parsePulsarWebSocketBase wsUrl))
  where
    outerContainerPort = pulsarProxyHttpNodePort
    wsUrl =
      "ws://" <> ipv4 <> ":" <> show outerContainerPort <> "/ws/v2"
    adminUrl =
      "http://" <> ipv4 <> ":" <> show outerContainerPort <> "/admin/v2"

transportFromBase :: String -> PulsarWebSocketBase -> PulsarTransport
transportFromBase adminUrl parsedWebSocketBase =
  PulsarTransport
    { pulsarAdminBaseUrl = Just adminUrl,
      pulsarWebSocketBase = parsedWebSocketBase
    }

eitherToMaybe :: Either a b -> Maybe b
eitherToMaybe (Right value) = Just value
eitherToMaybe (Left _) = Nothing

trimWhitespacePulsar :: String -> String
trimWhitespacePulsar = dropWhile (`elem` (" \t\n\r" :: String)) . reverse . dropWhile (`elem` (" \t\n\r" :: String)) . reverse

discoverPulsarTransportFromCluster ::
  ClusterConfig ->
  IO (Maybe PulsarTransport) ->
  IO (Maybe PulsarTransport)
discoverPulsarTransportFromCluster clusterConfig fallback =
  let rawWebSocketBase = Text.unpack (pulsarWsBaseUrl (clusterPulsar clusterConfig))
      adminBase = Text.unpack (pulsarAdminUrl (clusterPulsar clusterConfig))
   in if null rawWebSocketBase
        then fallback
        else parseClusterPulsarTransport adminBase rawWebSocketBase

parseClusterPulsarTransport :: String -> String -> IO (Maybe PulsarTransport)
parseClusterPulsarTransport adminBase rawWebSocketBase =
  case parsePulsarWebSocketBase rawWebSocketBase of
    Left err ->
      ioError (userError ("invalid pulsar.wsBaseUrl in cluster manifest: " <> err))
    Right parsedWebSocketBase ->
      pure
        ( Just
            PulsarTransport
              { pulsarAdminBaseUrl = if null adminBase then Nothing else Just adminBase,
                pulsarWebSocketBase = parsedWebSocketBase
              }
        )

-- | Baseline Kind NodePort host port for the in-cluster Pulsar proxy HTTP
-- surface (the Pulsar admin v2 API and the websocket endpoint). The trusted
-- Apple host-native service daemon reaches Pulsar directly through this
-- loopback NodePort rather than the Keycloak-JWT-gated @/pulsar/admin@ and
-- @/pulsar/ws@ Envoy edge routes, so its namespace reconcile never traverses
-- the operator-route SecurityPolicy. The in-cluster Kubernetes NodePort
-- stays @30080@, but the operator-host port is chosen dynamically at cluster
-- up (see @choosePulsarHttpPort@ in 'Infernix.Cluster') and persisted to
-- 'pulsarHttpPortPath'; this baseline is only the fallback used when that
-- file is absent.
defaultPulsarProxyHttpLoopbackHostPort :: Int
defaultPulsarProxyHttpLoopbackHostPort = pulsarProxyHttpNodePort

-- | In-cluster Kubernetes NodePort for the Pulsar-proxy HTTP surface
-- (the @/admin/v2@ admin API and the @/ws/v2@ websocket endpoint). This
-- is the un-gated proxy surface: kube-proxy binds it on every Kind node
-- interface, so the Linux outer-container launcher reaches it at
-- @<control-plane-ipv4>:30080@ once it has joined the @kind@ bridge (see
-- @ensureOuterContainerKindNetworkAccess@), exactly as it already reaches
-- the gateway NodePort. The Keycloak-JWT-gated @/pulsar/admin@ Envoy edge
-- route lives on the gateway NodePort (@gateway.publishedNodePort@, 30090)
-- instead and is reserved for browser/operator access.
pulsarProxyHttpNodePort :: Int
pulsarProxyHttpNodePort = 30080

discoverAppleHostPulsarTransport :: Paths -> IO (Maybe PulsarTransport)
discoverAppleHostPulsarTransport paths = do
  let publicationPath = publicationStatePath paths
  publicationPresent <- doesFileExist publicationPath
  if not publicationPresent
    then pure Nothing
    else do
      publicationPayload <- Lazy.readFile publicationPath
      case eitherDecode publicationPayload of
        Left _ -> pure Nothing
        Right publication ->
          if not (hostPublicationClusterPresent (publication :: HostDiscoveredPublication))
            then pure Nothing
            else do
              pulsarHttpPort <- fromMaybe defaultPulsarProxyHttpLoopbackHostPort <$> readPulsarHttpPortMaybe paths
              buildLoopbackNodePortTransport pulsarHttpPort
  where
    buildLoopbackNodePortTransport pulsarHttpPort =
      case parsePulsarWebSocketBase ("ws://127.0.0.1:" <> show pulsarHttpPort <> "/ws/v2") of
        Left err ->
          ioError
            ( userError
                ( "failed to construct the Apple host-native Pulsar websocket endpoint from the proxy NodePort:\n"
                    <> err
                )
            )
        Right websocketBase ->
          pure
            ( Just
                PulsarTransport
                  { pulsarAdminBaseUrl = Just ("http://127.0.0.1:" <> show pulsarHttpPort <> "/admin/v2"),
                    pulsarWebSocketBase = websocketBase
                  }
            )

ensureRegisteredSchemas :: Paths -> PulsarTransport -> DemoConfig -> IO ()
ensureRegisteredSchemas paths transport demoConfig = do
  ensureSchemaMarkers paths demoConfig
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  manager <- newManager defaultManagerSettings
  forM_ (requestLikeSchemaTopics demoConfig) $ \topicValue ->
    ensureRemoteSchema manager adminBaseUrl topicValue "infernix.runtime.InferenceRequest"
  forM_ (resultLikeSchemaTopics demoConfig) $ \topicValue ->
    ensureRemoteSchema manager adminBaseUrl topicValue "infernix.runtime.InferenceResult"

schemaTopicsForDemoConfig :: DemoConfig -> [Text.Text]
schemaTopicsForDemoConfig demoConfig =
  uniqueTexts (requestLikeSchemaTopics demoConfig <> resultLikeSchemaTopics demoConfig)

startupTopicsForDemoConfig :: DemoConfig -> [Text.Text]
startupTopicsForDemoConfig demoConfig =
  uniqueTexts (schemaTopicsForDemoConfig demoConfig <> modelBootstrapTopicsForDemoConfig demoConfig)

requestLikeSchemaTopics :: DemoConfig -> [Text.Text]
requestLikeSchemaTopics demoConfig =
  uniqueTexts
    ( requestTopics demoConfig
        <> daemonConfigRequestTopics (coordinatorDaemon demoConfig)
        <> concatMap daemonConfigRequestTopics (engineDaemons demoConfig)
    )

resultLikeSchemaTopics :: DemoConfig -> [Text.Text]
resultLikeSchemaTopics demoConfig =
  uniqueTexts
    ( resultTopic demoConfig
        : daemonConfigResultTopic (coordinatorDaemon demoConfig)
        : map daemonConfigResultTopic (engineDaemons demoConfig)
    )

modelBootstrapTopicsForDemoConfig :: DemoConfig -> [Text.Text]
modelBootstrapTopicsForDemoConfig demoConfig =
  uniqueTexts
    ( modelBootstrapTopic demoConfig
        : map
          (ConversationTopic.modelBootstrapReadyTopicName ConversationTopic.systemTopicNamespace . modelId)
          (models demoConfig)
    )

uniqueTexts :: [Text.Text] -> [Text.Text]
uniqueTexts = go []
  where
    go seen [] = reverse seen
    go seen (value : rest)
      | value `elem` seen = go seen rest
      | otherwise = go (value : seen) rest

ensureRegisteredSchemasWithRetry :: Paths -> PulsarTransport -> DemoConfig -> IO ()
ensureRegisteredSchemasWithRetry paths transport demoConfig =
  retry (1 :: Int)
  where
    retry attempt = do
      registrationResult <- try @SomeException (ensureRegisteredSchemas paths transport demoConfig)
      case registrationResult of
        Right _ -> pure ()
        Left err ->
          case fromException err :: Maybe SomeAsyncException of
            Just asyncErr -> throwIO asyncErr
            Nothing -> do
              hPutStrLn
                stderr
                ( "pulsar schema registration attempt "
                    <> show attempt
                    <> " failed:\n"
                    <> displayException err
                )
              threadDelay 1000000
              retry (attempt + 1)

-- | Phase 7 Sprint 7.7 + 7.5: reconcile the supported Pulsar tenants,
-- namespaces, and the @model.bootstrap.request@ topic on every daemon
-- startup. Idempotent — re-running against an already-reconciled broker
-- is cheap because each call either returns @409 Conflict@ (already
-- exists) or @204 No Content@ (policy already set).
--
-- The supported topology adds two namespaces:
--
--  * @infernix/system@ — carries the @model.bootstrap.request@ and
--    @model.bootstrap.ready.<modelId>@ topic family the coordinator's
--    Failover bootstrap subscription consumes.
--  * @infernix/demo@ — carries the per-context conversation log topics
--    and the compacted @demo.user.<userId>.contexts@ /
--    @demo.user.<userId>.drafts@ metadata topics. A namespace-level
--    compaction threshold ensures the compacted topics reach the
--    @compacted@ state without operator intervention.
--
-- The supported default Pulsar tenant / namespace for production
-- topics is @infernix/demo@ (Phase 7 Sprint 7.7, legacy row 21). The
-- @infernix@ tenant is created here so the supported demo and system
-- namespaces live in a dedicated tenant rather than the stock-Pulsar
-- @public/default@ defaults.
reconcileSupportedNamespaces :: PulsarTransport -> DemoConfig -> IO ()
reconcileSupportedNamespaces transport _demoConfig = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  manager <- newManager defaultManagerSettings
  -- Tenant + namespaces. Pulsar's tenant-create endpoint requires a
  -- non-empty 'allowedClusters' list pointing at real clusters (a
  -- @412 Precondition Failed@ comes back when we pass an empty array).
  -- Query @/admin/v2/clusters@ once and reuse the result for the
  -- tenant body so the supported reconcile works on any Pulsar
  -- release name.
  knownClusters <- listClusters manager adminBaseUrl
  ensureTenant manager adminBaseUrl "infernix" knownClusters
  ensureNamespace manager adminBaseUrl "infernix/system"
  ensureNamespace manager adminBaseUrl "infernix/demo"
  -- Compaction threshold on the demo namespace so the compacted contexts
  -- and drafts topics reach the supported steady state. 100 MiB (in
  -- bytes) matches Pulsar's documented small-namespace default.
  ensureNamespaceCompactionThreshold manager adminBaseUrl "infernix/demo" (100 * 1024 * 1024)
  -- Phase 7 Sprint 7.7: enable broker-side message deduplication on
  -- both supported namespaces. The full exactly-once contract also
  -- requires the producer to send a stable @producerName@ plus a
  -- monotonically increasing @sequenceId@ within that producer scope.
  -- WebSocket publishers express the sequence baseline through the
  -- @initialSequenceId@ URL parameter; frontend mutation producers use
  -- one-message mutation-scoped names so arbitrary client keys remain
  -- safe.
  ensureNamespaceDeduplicationEnabled manager adminBaseUrl "infernix/demo"
  ensureNamespaceDeduplicationEnabled manager adminBaseUrl "infernix/system"

reconcileSupportedNamespacesWithRetry :: PulsarTransport -> DemoConfig -> IO ()
reconcileSupportedNamespacesWithRetry transport demoConfig =
  retry (1 :: Int)
  where
    retry attempt = do
      reconcileResult <- try @SomeException (reconcileSupportedNamespaces transport demoConfig)
      case reconcileResult of
        Right _ -> pure ()
        Left err ->
          case fromException err :: Maybe SomeAsyncException of
            Just asyncErr -> throwIO asyncErr
            Nothing -> do
              hPutStrLn
                stderr
                ( "pulsar namespace reconcile attempt "
                    <> show attempt
                    <> " failed:\n"
                    <> displayException err
                )
              threadDelay 1000000
              retry (attempt + 1)

-- | Reconcile every static startup topic derived from the typed
-- 'DemoConfig' topology. This makes the coordinator/engine topic surface
-- explicit before schema registration, rather than relying on broker
-- auto-topic creation during first publish or first schema registration.
reconcileStartupTopics :: PulsarTransport -> DemoConfig -> IO ()
reconcileStartupTopics transport demoConfig = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  manager <- newManager defaultManagerSettings
  forM_ (startupTopicsForDemoConfig demoConfig) $
    ensureNonPartitionedTopic manager adminBaseUrl

reconcileStartupTopicsWithRetry :: PulsarTransport -> DemoConfig -> IO ()
reconcileStartupTopicsWithRetry transport demoConfig =
  retry (1 :: Int)
  where
    retry attempt = do
      reconcileResult <- try @SomeException (reconcileStartupTopics transport demoConfig)
      case reconcileResult of
        Right _ -> pure ()
        Left err ->
          case fromException err :: Maybe SomeAsyncException of
            Just asyncErr -> throwIO asyncErr
            Nothing -> do
              hPutStrLn
                stderr
                ( "pulsar topic reconcile attempt "
                    <> show attempt
                    <> " failed:\n"
                    <> displayException err
                )
              threadDelay 1000000
              retry (attempt + 1)

-- | Query @GET /admin/v2/clusters@ for the list of cluster names this
-- broker manages, used as the @allowedClusters@ value when reconciling
-- the supported tenant. The supported deployment is a single local
-- Pulsar cluster but its name is release-dependent
-- (`infernix-infernix-pulsar` for the bundled chart values), so the
-- daemon discovers it at startup rather than hardcoding.
listClusters :: Manager -> String -> IO [Text.Text]
listClusters manager adminBaseUrl = do
  requestValue <- parseRequest (adminBaseUrl <> "/clusters")
  response <- httpLbs requestValue manager
  case statusCode (responseStatus response) of
    200 ->
      case eitherDecode (responseBody response) of
        Right clusters -> pure clusters
        Left decodeError ->
          ioError
            ( userError
                ( "failed to parse Pulsar clusters list:\n"
                    <> decodeError
                )
            )
    code ->
      ioError
        ( userError
            ( "failed to list Pulsar clusters (status "
                <> show code
                <> "):\n"
                <> lazyBodyToString (responseBody response)
            )
        )

ensureTenant :: Manager -> String -> Text.Text -> [Text.Text] -> IO ()
ensureTenant manager adminBaseUrl tenantValue allowedClusters = do
  -- Pulsar admin v2 tenant create: PUT @/admin/v2/tenants/<tenant>@.
  -- The body declares allowed clusters and admin roles. Pulsar
  -- requires at least one real cluster name in 'allowedClusters' (a
  -- @412 Precondition Failed@ comes back when the list is empty), so
  -- the caller supplies the cluster list discovered via 'listClusters'.
  let url = adminBaseUrl <> "/tenants/" <> Text.unpack tenantValue
  putRequest <- parseRequest url
  let createRequest =
        putRequest
          { method = "PUT",
            requestHeaders = [("Content-Type", "application/json")],
            requestBody =
              RequestBodyLBS
                ( encode
                    ( object
                        [ "adminRoles" .= ([] :: [String]),
                          "allowedClusters" .= allowedClusters
                        ]
                    )
                )
          }
  response <- httpLbs createRequest manager
  let code = statusCode (responseStatus response)
  -- 204 = created/updated; 409 = already exists (treated as success).
  unless (code `elem` [200, 204, 409]) $
    ioError
      ( userError
          ( "failed to reconcile Pulsar tenant "
              <> Text.unpack tenantValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

ensureNamespace :: Manager -> String -> Text.Text -> IO ()
ensureNamespace manager adminBaseUrl namespaceValue = do
  let url = adminBaseUrl <> "/namespaces/" <> Text.unpack namespaceValue
  putRequest <- parseRequest url
  let createRequest =
        putRequest
          { method = "PUT",
            requestHeaders = [("Content-Type", "application/json")]
          }
  response <- httpLbs createRequest manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204, 409]) $
    ioError
      ( userError
          ( "failed to reconcile Pulsar namespace "
              <> Text.unpack namespaceValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

ensureNamespaceCompactionThreshold :: Manager -> String -> Text.Text -> Int -> IO ()
ensureNamespaceCompactionThreshold manager adminBaseUrl namespaceValue thresholdBytes = do
  let url = adminBaseUrl <> "/namespaces/" <> Text.unpack namespaceValue <> "/compactionThreshold"
  putRequest <- parseRequest url
  let createRequest =
        putRequest
          { method = "PUT",
            requestHeaders = [("Content-Type", "application/json")],
            requestBody = RequestBodyLBS (encode thresholdBytes)
          }
  response <- httpLbs createRequest manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204]) $
    ioError
      ( userError
          ( "failed to set Pulsar namespace compaction threshold for "
              <> Text.unpack namespaceValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

readNamespaceCompactionThresholdViaPulsar :: PulsarTransport -> Text.Text -> IO Int
readNamespaceCompactionThresholdViaPulsar transport namespaceValue = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  manager <- newManager defaultManagerSettings
  let url = adminBaseUrl <> "/namespaces/" <> Text.unpack namespaceValue <> "/compactionThreshold"
  requestValue <- parseRequest url
  response <- httpLbs requestValue manager
  case statusCode (responseStatus response) of
    200 ->
      case eitherDecode (responseBody response) of
        Right threshold -> pure threshold
        Left decodeError ->
          ioError
            ( userError
                ( "failed to parse Pulsar namespace compaction threshold for "
                    <> Text.unpack namespaceValue
                    <> ":\n"
                    <> decodeError
                )
            )
    code ->
      ioError
        ( userError
            ( "failed to read Pulsar namespace compaction threshold for "
                <> Text.unpack namespaceValue
                <> " (status "
                <> show code
                <> "):\n"
                <> lazyBodyToString (responseBody response)
            )
        )

triggerTopicCompactionViaPulsar :: PulsarTransport -> Text.Text -> IO ()
triggerTopicCompactionViaPulsar transport topicValue = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  topicRef <- requireTopicRef topicValue
  manager <- newManager defaultManagerSettings
  requestValue <- parseRequest (topicCompactionUrl adminBaseUrl topicRef)
  let compactRequest =
        requestValue
          { method = "PUT",
            requestHeaders = [("Content-Type", "application/json")]
          }
  response <- httpLbs compactRequest manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 202, 204]) $
    ioError
      ( userError
          ( "failed to trigger Pulsar topic compaction for "
              <> Text.unpack topicValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

waitForTopicCompactionCompleteViaPulsar :: PulsarTransport -> Text.Text -> IO ()
waitForTopicCompactionCompleteViaPulsar transport topicValue = go (60 :: Int)
  where
    go attemptsRemaining
      | attemptsRemaining <= 0 =
          ioError (userError ("timed out waiting for Pulsar topic compaction for " <> Text.unpack topicValue))
      | otherwise = do
          statusValue <- readTopicCompactionStatusViaPulsar transport topicValue
          case Text.toUpper (longRunningProcessStatus statusValue) of
            "SUCCESS" -> pure ()
            "ERROR" ->
              ioError
                ( userError
                    ( "Pulsar topic compaction failed for "
                        <> Text.unpack topicValue
                        <> maybe "" ((": " <>) . Text.unpack) (longRunningProcessLastError statusValue)
                    )
                )
            _ -> do
              threadDelay 1000000
              go (attemptsRemaining - 1)

readTopicCompactionStatusViaPulsar :: PulsarTransport -> Text.Text -> IO LongRunningProcessStatus
readTopicCompactionStatusViaPulsar transport topicValue = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  topicRef <- requireTopicRef topicValue
  manager <- newManager defaultManagerSettings
  requestValue <- parseRequest (topicCompactionUrl adminBaseUrl topicRef)
  response <- httpLbs requestValue manager
  case statusCode (responseStatus response) of
    200 ->
      case eitherDecode (responseBody response) of
        Right statusValue -> pure statusValue
        Left decodeError ->
          ioError
            ( userError
                ( "failed to parse Pulsar topic compaction status for "
                    <> Text.unpack topicValue
                    <> ":\n"
                    <> decodeError
                    <> "\n"
                    <> lazyBodyToString (responseBody response)
                )
            )
    code ->
      ioError
        ( userError
            ( "failed to read Pulsar topic compaction status for "
                <> Text.unpack topicValue
                <> " (status "
                <> show code
                <> "):\n"
                <> lazyBodyToString (responseBody response)
            )
        )

topicCompactionUrl :: String -> TopicRef -> String
topicCompactionUrl adminBaseUrl topicRef =
  trimTrailingSlash adminBaseUrl
    <> "/persistent/"
    <> Text.unpack (topicTenant topicRef)
    <> "/"
    <> Text.unpack (topicNamespace topicRef)
    <> "/"
    <> Text.unpack (topicName topicRef)
    <> "/compaction"

topicDeleteUrl :: String -> TopicRef -> String
topicDeleteUrl adminBaseUrl topicRef =
  trimTrailingSlash adminBaseUrl
    <> "/persistent/"
    <> Text.unpack (topicTenant topicRef)
    <> "/"
    <> Text.unpack (topicNamespace topicRef)
    <> "/"
    <> Text.unpack (topicName topicRef)
    <> "?force=true"

-- | Enable broker-side message deduplication on a namespace via the
-- admin API. With this policy on, the broker tracks
-- @(producerName, sequenceId)@ pairs and rejects duplicates. The
-- producer-side wiring supplies stable @producerName@ + monotonic
-- @sequenceId@ values; Sprint 7.14's chaos validation proves the
-- duplicate-collapse behavior on a real broker.
ensureNamespaceDeduplicationEnabled :: Manager -> String -> Text.Text -> IO ()
ensureNamespaceDeduplicationEnabled manager adminBaseUrl namespaceValue = do
  let url = adminBaseUrl <> "/namespaces/" <> Text.unpack namespaceValue <> "/deduplication"
  putRequest <- parseRequest url
  let createRequest =
        putRequest
          { method = "POST",
            requestHeaders = [("Content-Type", "application/json")],
            requestBody = RequestBodyLBS (encode True)
          }
  response <- httpLbs createRequest manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204]) $
    ioError
      ( userError
          ( "failed to enable Pulsar namespace deduplication for "
              <> Text.unpack namespaceValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

ensureNonPartitionedTopic :: Manager -> String -> Text.Text -> IO ()
ensureNonPartitionedTopic manager adminBaseUrl topicValue = do
  topicRef <- requireTopicRef topicValue
  -- PUT @/admin/v2/persistent/<tenant>/<namespace>/<topic>@ creates a
  -- non-partitioned persistent topic; 409 is the already-exists case.
  let url =
        adminBaseUrl
          <> "/persistent/"
          <> Text.unpack (topicTenant topicRef)
          <> "/"
          <> Text.unpack (topicNamespace topicRef)
          <> "/"
          <> Text.unpack (topicName topicRef)
  putRequest <- parseRequest url
  let createRequest =
        putRequest
          { method = "PUT",
            requestHeaders = [("Content-Type", "application/json")]
          }
  response <- httpLbs createRequest manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204, 409]) $
    ioError
      ( userError
          ( "failed to reconcile Pulsar topic "
              <> Text.unpack topicValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

deleteTopicViaPulsar :: Manager -> String -> Text.Text -> IO ()
deleteTopicViaPulsar manager adminBaseUrl topicValue = do
  topicRef <- requireTopicRef topicValue
  deleteRequest <- parseRequest (topicDeleteUrl adminBaseUrl topicRef)
  response <- httpLbs (deleteRequest {method = "DELETE"}) manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204, 404]) $
    ioError
      ( userError
          ( "failed to delete Pulsar topic "
              <> Text.unpack topicValue
              <> " (status "
              <> show code
              <> "):\n"
              <> lazyBodyToString (responseBody response)
          )
      )

requirePulsarAdminBaseUrl :: PulsarTransport -> IO String
requirePulsarAdminBaseUrl transport =
  case pulsarAdminBaseUrl transport of
    Just adminBaseUrl -> pure adminBaseUrl
    Nothing ->
      ioError
        ( userError
            "Pulsar admin URL must be configured (ClusterConfig.pulsar.adminUrl) whenever the real Pulsar transport is enabled."
        )

ensureRemoteSchema :: Manager -> String -> Text.Text -> String -> IO ()
ensureRemoteSchema manager adminBaseUrl topicValue messageTypeName = do
  topicRef <- requireTopicRef topicValue
  requestValue <- parseRequest (schemaUrl adminBaseUrl topicRef)
  existingResponse <- httpLbs requestValue manager
  case statusCode (responseStatus existingResponse) of
    200 -> pure ()
    404 -> createSchema requestValue
    code ->
      ioError
        ( userError
            ( "unexpected Pulsar schema response for "
                <> Text.unpack topicValue
                <> " (status "
                <> show code
                <> "):\n"
                <> lazyBodyToString (responseBody existingResponse)
            )
        )
  where
    createSchema requestValue = do
      let schemaPayload =
            encode $
              object
                [ "type" .= ("BYTES" :: String),
                  "schema" .= ("" :: String),
                  "properties"
                    .= object
                      [ "contentType" .= ("application/protobuf" :: String),
                        "messageType" .= messageTypeName
                      ]
                ]
          createRequest =
            requestValue
              { method = "POST",
                requestHeaders = [("Content-Type", "application/json")],
                requestBody = RequestBodyLBS schemaPayload
              }
      createResponse <- httpLbs createRequest manager
      let code = statusCode (responseStatus createResponse)
      unless (code `elem` [200, 201, 204, 409]) $
        ioError
          ( userError
              ( "failed to register Pulsar schema for "
                  <> Text.unpack topicValue
                  <> " (status "
                  <> show code
                  <> "):\n"
                  <> lazyBodyToString (responseBody createResponse)
              )
          )

consumeTopicForever ::
  PulsarTransport ->
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  DaemonConfig ->
  DemoConfig ->
  Maybe KVCache.EngineKVCache ->
  MVar () ->
  Text.Text ->
  IO ()
consumeTopicForever transport paths runtimeMode overrides daemonConfig demoConfig maybeEngineKVCache engineExecutionLock requestTopicValue =
  case serviceConsumerSubscriptionTypeForTopic runtimeMode daemonConfig requestTopicValue of
    Left err -> ioError (userError err)
    Right subscriptionType ->
      forever $ do
        sessionResult <- try @SomeException (consumeTopicSession transport paths runtimeMode overrides daemonConfig demoConfig maybeEngineKVCache engineExecutionLock requestTopicValue subscriptionType)
        case sessionResult of
          Right _ -> threadDelay 1000000
          Left err
            | isFatalServiceConsumerError subscriptionType err -> do
                hPutStrLn
                  stderr
                  ( "pulsar consumer subscription rejected for "
                      <> Text.unpack requestTopicValue
                      <> " with "
                      <> Text.unpack (consumerSubscriptionTypeId subscriptionType)
                      <> " ownership:\n"
                      <> displayException err
                  )
                throwIO err
            | otherwise -> do
                hPutStrLn
                  stderr
                  ( "pulsar consumer loop failed for "
                      <> Text.unpack requestTopicValue
                      <> ":\n"
                      <> displayException err
                  )
                threadDelay 1000000

isFatalServiceConsumerError :: ConsumerSubscriptionType -> SomeException -> Bool
isFatalServiceConsumerError subscriptionType err =
  subscriptionType == ConsumerExclusive
    && any (`Text.isInfixOf` errorText) ["409", "conflict", "exclusive", "consumer busy"]
  where
    errorText = Text.toLower (Text.pack (displayException err))

serviceConsumerSubscriptionType :: RuntimeMode -> DaemonConfig -> Either String ConsumerSubscriptionType
serviceConsumerSubscriptionType runtimeMode daemonConfig =
  serviceConsumerSubscriptionTypeForTopic runtimeMode daemonConfig ""

serviceConsumerSubscriptionTypeForTopic :: RuntimeMode -> DaemonConfig -> Text.Text -> Either String ConsumerSubscriptionType
serviceConsumerSubscriptionTypeForTopic runtimeMode daemonConfig requestTopicValue
  | selectedType == ConsumerFailover =
      Left "service consumers must not use Failover; Failover is reserved for coordinator-owned dispatcher, result-bridge, and model-bootstrap leadership loops"
  | daemonConfigRole daemonConfig /= Engine && selectedType /= ConsumerShared =
      Left "coordinator service consumers use Shared; Exclusive is reserved for pinned engine member routes"
  | daemonConfigRole daemonConfig == Engine
      && isPinnedEngineMemberTopic runtimeMode requestTopicValue =
      Right ConsumerExclusive
  | otherwise = Right selectedType
  where
    selectedType =
      fromMaybe ConsumerShared (daemonConfigConsumerSubscriptionType daemonConfig)

isPinnedEngineMemberTopic :: RuntimeMode -> Text.Text -> Bool
isPinnedEngineMemberTopic runtimeMode requestTopicValue =
  pinnedPrefix `Text.isPrefixOf` requestTopicValue
  where
    pinnedPrefix =
      "persistent://infernix/demo/inference.batch."
        <> runtimeModeId runtimeMode
        <> ".member."

consumeTopicSession ::
  PulsarTransport ->
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  DaemonConfig ->
  DemoConfig ->
  Maybe KVCache.EngineKVCache ->
  MVar () ->
  Text.Text ->
  ConsumerSubscriptionType ->
  IO ()
consumeTopicSession transport paths runtimeMode overrides daemonConfig demoConfig maybeEngineKVCache engineExecutionLock requestTopicValue subscriptionType = do
  processLabel <- currentProcessLabel
  topicRef <- requireTopicRef requestTopicValue
  let subscriptionName = "infernix-service-" <> sanitizeTopic requestTopicValue
      consumerName = serviceConsumerName subscriptionName subscriptionType processLabel
      consumerPath =
        buildServiceConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          subscriptionName
          consumerName
          subscriptionType
  runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
    forever $ do
      rawEnvelope <- receiveJsonFrame "Pulsar consumer message" connection
      envelope <- decodeJsonText "Pulsar consumer message" rawEnvelope
      handled <- try @SomeException (handleConsumerEnvelope connection envelope)
      case handled of
        Right _ -> pure ()
        Left err -> do
          sendNegativeAck connection (envelopeMessageId envelope)
          hPutStrLn
            stderr
            ( "pulsar message handling failed for "
                <> Text.unpack requestTopicValue
                <> ":\n"
                <> displayException err
            )
  where
    handleConsumerEnvelope connection envelope = do
      decodedRequest <- decodeEnvelopePayload "inference request" envelope
      -- Coordinator-role handoff routes through the validated engine-pool
      -- graph. Engine-role consumers execute the request and publish the
      -- typed result.
      case daemonConfigRole daemonConfig of
        Coordinator -> do
          selectedBatchTopicValue <-
            case batchTopicForRequest runtimeMode demoConfig decodedRequest of
              Left err ->
                ioError (userError err)
              Right topicValue ->
                pure topicValue
          -- Coordinator-role hand-off to the engine-batch topic. The
          -- producer name is stable per coordinator role so the broker
          -- dedups concurrent coordinator replicas. Sequence-id
          -- derivation from the application-level
          -- @userPromptMessageId@ key lives in
          -- @Infernix.Dispatch.SingleFlight.producerDedupSequenceId@;
          -- the broker-side dedup gate ('reconcileSupportedNamespaces')
          -- accepts the resulting tuple. Phase 7 Sprint 7.14 wires the
          -- typed envelope read here.
          let requestContextId = view ProtoInferenceFields.contextId decodedRequest
              batchProducerScope =
                if Text.null requestContextId
                  then "infernix-coordinator-batch-" <> runtimeModeId runtimeMode
                  else "infernix-coordinator-batch-" <> runtimeModeId runtimeMode <> "-" <> requestContextId
              batchOptions = inferenceRequestPublishOptions batchProducerScope decodedRequest
          publishTopicPayload
            transport
            selectedBatchTopicValue
            batchOptions
            (view ProtoInferenceFields.requestId decodedRequest)
            (encodeMessage decodedRequest)
        Engine ->
          modifyMVar_ engineExecutionLock $ \() -> do
            let modelIdValue = view ProtoInferenceFields.requestModelId decodedRequest
                requestIdValue = view ProtoInferenceFields.requestId decodedRequest
            publishedResult <-
              if Text.null modelIdValue
                then pure (emptyModelIdRejectionResult runtimeMode decodedRequest)
                else publishedResultFromRequest (Just transport) paths runtimeMode overrides maybeEngineKVCache decodedRequest
            -- Phase 7 Sprint 7.14 follow-on (2026-05-30): one-line trace per
            -- engine-side inference so the host daemon log surfaces the
            -- request id, resolved model id, and final status. Diagnoses
            -- empty-model-id rejection vs adapter failure vs success without
            -- attaching a debugger.
            putStrLn
              ( "engineProcessed: request="
                  <> Text.unpack requestIdValue
                  <> " model="
                  <> Text.unpack modelIdValue
                  <> " status="
                  <> Text.unpack (status publishedResult)
              )
            let publishedResultContextId = resultContextId publishedResult
                resultProducerScope =
                  if Text.null publishedResultContextId
                    then "infernix-engine-result-" <> runtimeModeId runtimeMode
                    else "infernix-engine-result-" <> runtimeModeId runtimeMode <> "-" <> publishedResultContextId
                resultOptions = inferenceRequestPublishOptions resultProducerScope decodedRequest
            publishTopicPayload
              transport
              (daemonConfigResultTopic daemonConfig)
              resultOptions
              (requestId publishedResult)
              (encodeMessage (domainResultToProto publishedResult))
            pure ()
        Webapp ->
          ioError (userError "webapp role does not consume inference topics")
      sendAck connection (envelopeMessageId envelope)

serviceConsumerAckTimeoutMillis :: Int
serviceConsumerAckTimeoutMillis = 900000

serviceConsumerName :: String -> ConsumerSubscriptionType -> Text.Text -> String
serviceConsumerName subscriptionName subscriptionType processLabel =
  case subscriptionType of
    ConsumerFailover ->
      Text.unpack (PulsarFailover.failoverConsumerName (Text.pack subscriptionName) processLabel)
    _ -> subscriptionName <> "-consumer-" <> sanitizeTopic processLabel

batchTopicForRequest :: RuntimeMode -> DemoConfig -> ProtoInference.InferenceRequest -> Either String Text.Text
batchTopicForRequest runtimeMode demoConfig requestValue =
  case findModel runtimeMode modelIdValue >>= const (enginePoolForModel demoConfig modelIdValue) of
    Just pool -> Right (enginePoolTopicForMode runtimeMode (enginePoolId pool) modelIdValue)
    Nothing ->
      Left
        ( "no engine pool route for model "
            <> Text.unpack modelIdValue
            <> " on "
            <> Text.unpack (runtimeModeId runtimeMode)
        )
  where
    modelIdValue = view ProtoInferenceFields.requestModelId requestValue

-- | Phase 7 Sprint 7.7 producer-side dedup wiring. Each publish carries
-- a stable @producerName@ in the URL query. For the WebSocket API, the
-- sequence baseline is also a producer query parameter
-- (@initialSequenceId@), not a message JSON field. Because this module
-- opens one WebSocket producer per publish, a requested message
-- sequence @N@ is represented as @initialSequenceId = N - 1@ so the
-- first and only message on that producer has sequence @N@. The
-- broker-side dedup gate reconciled by 'reconcileSupportedNamespaces'
-- rejects duplicate @(producerName, sequenceId)@ tuples.
data PublishOptions = PublishOptions
  { publishProducerName :: Text.Text,
    publishMessageKey :: Maybe Text.Text,
    publishSequenceId :: Maybe Integer
  }

defaultPublishOptions :: Text.Text -> PublishOptions
defaultPublishOptions producerName =
  PublishOptions
    { publishProducerName = producerName,
      publishMessageKey = Nothing,
      publishSequenceId = Nothing
    }

inferenceRequestPublishOptions :: Text.Text -> ProtoInference.InferenceRequest -> PublishOptions
inferenceRequestPublishOptions producerScope request =
  (defaultPublishOptions producerName)
    { publishSequenceId = inferenceRequestSequenceId request
    }
  where
    requestIdValue = view ProtoInferenceFields.requestId request
    userPromptMessageId = view ProtoInferenceFields.userPromptMessageId request
    producerName =
      inferenceRequestProducerNameForFields producerScope requestIdValue userPromptMessageId

-- | Producer name used with 'inferenceRequestSequenceId'. Durable prompt
-- envelopes keep the context-scoped producer because their
-- @userPromptMessageId@ maps to a monotonic Pulsar message sequence. Direct
-- @publishInferenceRequest@ callers do not carry that causal id; their fallback
-- sequence is a stable hash of the generated @requestId@, so the producer must
-- also be request-scoped. Pulsar dedup stores the highest sequence per
-- producer, not an unordered set of @(producer, sequence)@ pairs.
inferenceRequestProducerNameForFields :: Text.Text -> Text.Text -> Text.Text -> Text.Text
inferenceRequestProducerNameForFields producerScope requestIdValue userPromptMessageId
  | isJust (parseMessageIdToSequenceId userPromptMessageId) = producerScope
  | Text.null requestIdValue = producerScope
  | otherwise = dedupProducerName producerScope requestIdValue

-- | Derive a per-message Pulsar dedup @sequenceId@. Durable prompt envelopes
-- use @userPromptMessageId@: Pulsar MessageIds serialize as
-- @<ledgerId>:<entryId>:<partition>:<batchIdx>@; we pack ledger and entry into a
-- 64-bit value because both are monotonic per topic-partition. Direct
-- @publishInferenceRequest@ callers fall back to the generated @requestId@
-- hash, which must be paired with 'inferenceRequestProducerNameForFields' so
-- unordered hashes do not share one broker dedup cursor.
inferenceRequestSequenceId :: ProtoInference.InferenceRequest -> Maybe Integer
inferenceRequestSequenceId request =
  inferenceRequestSequenceIdForFields
    (view ProtoInferenceFields.requestId request)
    (view ProtoInferenceFields.userPromptMessageId request)

inferenceRequestSequenceIdForFields :: Text.Text -> Text.Text -> Maybe Integer
inferenceRequestSequenceIdForFields requestIdValue userPromptMessageId =
  parseMessageIdToSequenceId userPromptMessageId
    <|> directRequestSequenceId
  where
    directRequestSequenceId
      | Text.null requestIdValue = Nothing
      | otherwise = Just (stableSequenceId requestIdValue)

parseMessageIdToSequenceId :: Text.Text -> Maybe Integer
parseMessageIdToSequenceId raw =
  parseColonMessageId raw <|> parseWebSocketMessageId raw
  where
    parseColonMessageId value =
      case Text.splitOn ":" value of
        (ledgerText : entryText : _) -> do
          ledger <- parseInteger ledgerText
          entry <- parseInteger entryText
          pure (ledger * (2 ^ (32 :: Int)) + entry)
        _ -> Nothing
    parseInteger value =
      case reads (Text.unpack value) :: [(Integer, String)] of
        [(parsed, "")] -> Just parsed
        _ -> Nothing
    parseWebSocketMessageId value = do
      rawBytes <- either (const Nothing) Just (Base64.decode (TextEncoding.encodeUtf8 value))
      fields <- parseVarintFields rawBytes
      ledger <- listToMaybe [fieldValue | (1, fieldValue) <- fields]
      entry <- listToMaybe [fieldValue | (2, fieldValue) <- fields]
      pure (ledger * (2 ^ (32 :: Int)) + entry)

parseVarintFields :: ByteString.ByteString -> Maybe [(Int, Integer)]
parseVarintFields bytes
  | ByteString.null bytes = Just []
  | otherwise = do
      (tag, afterTag) <- decodeUnsignedVarint bytes
      let fieldNumber = fromIntegral (tag `div` 8)
          wireType = tag `mod` 8
      if fieldNumber <= (0 :: Int) || wireType /= 0
        then Nothing
        else do
          (fieldValue, afterValue) <- decodeUnsignedVarint afterTag
          remainingFields <- parseVarintFields afterValue
          pure ((fieldNumber, fieldValue) : remainingFields)

decodeUnsignedVarint :: ByteString.ByteString -> Maybe (Integer, ByteString.ByteString)
decodeUnsignedVarint = go 0 0
  where
    go shift acc bytes =
      case ByteString.uncons bytes of
        Nothing -> Nothing
        Just (byte, remaining) ->
          let chunk = toInteger (byte .&. 0x7f)
              nextAcc = acc + shiftL chunk shift
           in if byte .&. 0x80 == 0
                then Just (nextAcc, remaining)
                else
                  if shift >= (63 :: Int)
                    then Nothing
                    else go (shift + 7) nextAcc remaining

publishTopicPayload :: PulsarTransport -> Text.Text -> PublishOptions -> Text.Text -> ByteString.ByteString -> IO ()
publishTopicPayload transport topicValue options contextValue payload = do
  topicRef <- requireTopicRef topicValue
  let producerPath =
        buildProducerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          (publishProducerName options)
          (publishSequenceId options)
      baseFields =
        [ "payload" .= TextEncoding.decodeUtf8 (Base64.encode payload),
          "context" .= contextValue
        ]
      keyedFields =
        case publishMessageKey options of
          Just messageKey -> ("key" .= messageKey) : baseFields
          Nothing -> baseFields
      producerPayload = object keyedFields
      maxAttempts =
        if isJust (publishSequenceId options)
          then pulsarDeduplicatedProducerPublishAttempts
          else 1
  publishWithAttempt producerPath producerPayload maxAttempts (1 :: Int)
  where
    publishWithAttempt producerPath producerPayload maxAttempts attempt = do
      result <- try @SomeException (publishOnce producerPath producerPayload)
      case result of
        Right () -> pure ()
        Left err
          | isAsyncException err -> throwIO err
          | attempt < maxAttempts -> do
              hPutStrLn
                stderr
                ( "Pulsar publish attempt "
                    <> show attempt
                    <> " for "
                    <> Text.unpack topicValue
                    <> " failed; retrying deduplicated publish:\n"
                    <> displayException err
                )
              threadDelay pulsarProducerPublishRetryDelayMicros
              publishWithAttempt producerPath producerPayload maxAttempts (attempt + 1)
          | otherwise -> throwIO err
    publishOnce producerPath producerPayload =
      runPulsarWebSocketClient (pulsarWebSocketBase transport) producerPath $ \connection -> do
        sendJsonFrame connection producerPayload
        maybeRawResponse <- timeout pulsarProducerResponseTimeoutMicros (receiveJsonFrame "Pulsar producer response" connection)
        rawResponse <-
          case maybeRawResponse of
            Just response -> pure response
            Nothing ->
              ioError
                ( userError
                    ( "timed out waiting for Pulsar producer response for "
                        <> Text.unpack topicValue
                    )
                )
        producerResponse <- decodeJsonText "Pulsar producer response" rawResponse
        when (producerResult producerResponse /= "ok") $
          ioError
            ( userError
                ( "failed to publish Pulsar message for "
                    <> Text.unpack topicValue
                    <> ":\n"
                    <> Text.unpack (fromMaybe "unknown producer error" (producerErrorMessage producerResponse))
                )
            )

pulsarProducerResponseTimeoutMicros :: Int
pulsarProducerResponseTimeoutMicros = 30_000_000

pulsarDeduplicatedProducerPublishAttempts :: Int
pulsarDeduplicatedProducerPublishAttempts = 5

pulsarProducerPublishRetryDelayMicros :: Int
pulsarProducerPublishRetryDelayMicros = 1_000_000

-- | Phase 7 Sprint 7.8 result-bridge runtime loop. The coordinator
-- subscribes to the substrate's @inference.result.<mode>@ topic with a
-- Failover subscription (so exactly one coordinator replica is active
-- at a time; on crash the broker promotes a surviving replica and
-- redelivers any unacked message), decodes each result envelope,
-- derives the matching 'ConversationInferenceResultEvent', and
-- publishes it to the originating per-context conversation topic with
-- producer-side dedup keyed by @userPromptMessageId@. The substrate's
-- conversation topic family lives under
-- 'Infernix.Conversation.Topic.TopicNamespace' (default
-- @infernix/demo@); the bridge expects the upstream engine to have
-- populated 'resultUserId' / 'resultContextId' / 'resultCausalRef' on
-- the wire (these are the Sprint 7.8 envelope additions). Results
-- missing those fields belong to the legacy / Phase 4 manual-inference
-- path and are skipped without an ack-failure so they re-deliver
-- harmlessly on the next subscription session.
runResultBridgeLoop ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  ConversationTopic.TopicNamespace ->
  IO ()
runResultBridgeLoop transport runtimeMode resultTopic topicNamespace = do
  topicRef <- requireTopicRef resultTopic
  processLabel <- currentProcessLabel
  let runtimeModeText = runtimeModeId runtimeMode
      subscriptionName = "result-bridge-" <> runtimeModeText
      consumerName = PulsarFailover.failoverConsumerName subscriptionName processLabel
      consumerPath =
        buildFailoverConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          (Text.unpack subscriptionName)
          (Text.unpack consumerName)
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
            forever (handleResultBridgeMessage transport runtimeMode topicNamespace connection)
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "result-bridge session for "
              <> Text.unpack resultTopic
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

handleResultBridgeMessage ::
  PulsarTransport ->
  RuntimeMode ->
  ConversationTopic.TopicNamespace ->
  WebSockets.Connection ->
  IO ()
handleResultBridgeMessage transport _runtimeMode topicNamespace connection = do
  rawEnvelope <- receiveJsonFrame "Pulsar result-bridge message" connection
  envelope <- decodeJsonText "Pulsar result-bridge message" rawEnvelope
  handled <-
    try @SomeException
      ( do
          protoResult <- decodeEnvelopePayload "inference result" envelope
          case protoResultToDomain protoResult of
            Nothing ->
              hPutStrLn
                stderr
                ( "result-bridge skipping undecodable inference result "
                    <> Text.unpack (envelopeMessageId envelope)
                )
            Just resultValue
              | Text.null (resultUserId resultValue)
                  || Text.null (resultContextId resultValue)
                  || Text.null (resultCausalRef resultValue) ->
                  -- Legacy / Phase 4 result without durable-context
                  -- routing fields. Skip silently so the legacy
                  -- manual-inference path is not broken by the bridge.
                  pure ()
              | otherwise -> bridgeResultToConversation transport topicNamespace resultValue
      )
  case handled of
    Right _ -> sendAck connection (envelopeMessageId envelope)
    Left err -> do
      sendNegativeAck connection (envelopeMessageId envelope)
      hPutStrLn
        stderr
        ( "result-bridge message handling failed:\n"
            <> displayException err
        )

-- | Publish a @ConversationInferenceResultEvent@ on the per-context
-- conversation topic for the given result. The producer name is
-- stable per @(role, contextId)@ so the broker dedup gate collapses
-- replays from a restarted bridge replica; the sequence id is derived
-- from the application-level @userPromptMessageId@ dedup key.
bridgeResultToConversation ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  InferenceResult ->
  IO ()
bridgeResultToConversation transport topicNamespace resultValue = do
  let userIdText = resultUserId resultValue
      contextIdText = resultContextId resultValue
      causalRef = resultCausalRef resultValue
      conversationTopic =
        ConversationTopic.conversationTopicName
          topicNamespace
          (Contracts.UserId userIdText)
          (Contracts.ContextId contextIdText)
      authorizedObjectRefs = authorizedGeneratedResultObjectRefs resultValue
      (inlineOutputValue, statusValue, objectRefValue) =
        conversationResultEventFields resultValue authorizedObjectRefs
      conversationEvent =
        ResultBridge.inferenceResultEventFor
          (Contracts.MessageId causalRef)
          statusValue
          inlineOutputValue
          objectRefValue
      options =
        (defaultPublishOptions ("infernix-result-bridge-" <> contextIdText))
          { publishSequenceId = parseMessageIdToSequenceId causalRef
          }
  publishTopicPayload
    transport
    conversationTopic
    options
    causalRef
    (Lazy.toStrict (encode conversationEvent))

conversationResultEventFields ::
  InferenceResult ->
  Either Text.Text [Contracts.ObjectRef] ->
  (Maybe Text.Text, Text.Text, [Contracts.ObjectRef])
conversationResultEventFields resultValue authorizedObjectRefs =
  case authorizedObjectRefs of
    Left rejectionMessage -> (Just rejectionMessage, "failed", [])
    Right refs -> (resultInlineOutput resultValue, status resultValue, refs)

resultInlineOutput :: InferenceResult -> Maybe Text.Text
resultInlineOutput resultValue =
  case payload resultValue of
    ResultPayload {inlineOutput = Just text} -> Just text
    _ -> Nothing

authorizedGeneratedResultObjectRefs :: InferenceResult -> Either Text.Text [Contracts.ObjectRef]
authorizedGeneratedResultObjectRefs resultValue =
  case payload resultValue of
    ResultPayload {objectRef = Just rawObjectRef} ->
      (: []) <$> authorizedGeneratedObjectRef (resultUserId resultValue) (resultContextId resultValue) rawObjectRef
    _ -> Right []

authorizedGeneratedObjectRef :: Text.Text -> Text.Text -> Text.Text -> Either Text.Text Contracts.ObjectRef
authorizedGeneratedObjectRef userIdText contextIdText rawObjectRef
  | Text.null userIdText || Text.null contextIdText =
      Left "generated artifact object reference rejected: result is missing durable user/context ownership"
  | otherwise =
      case parseStructuredObjectRef rawObjectRef of
        Nothing ->
          Left ("generated artifact object reference rejected: expected bucket/key, got " <> rawObjectRef)
        Just objectReference ->
          if objectRefTargetsGeneratedPrefix userIdText contextIdText objectReference
            then Right objectReference
            else Left ("generated artifact object reference rejected outside authorized generated prefix: " <> rawObjectRef)

objectRefTargetsGeneratedPrefix :: Text.Text -> Text.Text -> Contracts.ObjectRef -> Bool
objectRefTargetsGeneratedPrefix userIdText contextIdText objectReference =
  Contracts.objectBucket objectReference == demoObjectsBucketText
    && ObjLayout.generatedObjectPrefix (Contracts.UserId userIdText) (Contracts.ContextId contextIdText)
      `Text.isPrefixOf` Contracts.objectKey objectReference

demoObjectsBucketText :: Text.Text
demoObjectsBucketText =
  let ObjLayout.DemoObjectsBucket bucket = ObjLayout.defaultDemoObjectsBucket
   in bucket

parseStructuredObjectRef :: Text.Text -> Maybe Contracts.ObjectRef
parseStructuredObjectRef raw =
  let (bucket, rawKey) = Text.breakOn "/" raw
      key = Text.drop 1 rawKey
   in if Text.null bucket || Text.null key || Text.null rawKey
        then Nothing
        else
          Just
            Contracts.ObjectRef
              { Contracts.objectBucket = bucket,
                Contracts.objectKey = key
              }

-- | Phase 7 Sprint 7.6 per-context single-flight dispatcher loop. The
-- coordinator polls the supported demo namespace for
-- @demo.conversation.<userId>.<contextId>@ topics every
-- 'dispatcherTopicPollSeconds' seconds and forks one per-context worker
-- per topic. Each worker subscribes Failover with subscription name
-- @dispatcher-<contextId>@ (so exactly one coordinator replica is
-- active for a given context at a time), folds conversation events
-- through 'Infernix.Conversation.Reducer.stepReducer', and publishes
-- 'Infernix.Dispatch.SingleFlight.InferenceRequestEnvelope' as an
-- 'InferenceRequest' proto on the substrate's request topic. The
-- producer name is stable per context (@dispatcher-<contextId>@) and
-- the sequence id is derived from the prompt's
-- @userPromptMessageId@ so 'reconcileSupportedNamespaces' broker
-- dedup collapses retries from a crashed-and-recovered dispatcher
-- without a duplicate inference dispatch.
--
-- The dispatcher does not own model-id resolution: the published
-- proto carries the dispatcher envelope (causal_ref, prefix_hash,
-- conversation_log_offset, user_id, context_id) plus an empty
-- @request_model_id@ until the SPA-side @CreateContext@ surface
-- (Sprint 7.10 + 7.12) writes per-context model metadata to
-- @demo.user.<userId>.contexts@. Until that lookup is wired in,
-- the dispatcher publishes envelopes that the engine will reject;
-- the integration loop in Sprint 7.14 covers the end-to-end gate.
dispatcherTopicPollSeconds :: Int
dispatcherTopicPollSeconds = 30

runDispatcherLoop ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  ConversationTopic.TopicNamespace ->
  ContextModelMap ->
  [ModelDescriptor] ->
  IO ()
runDispatcherLoop transport runtimeMode requestTopic topicNamespace contextModelMap modelCatalog
  | Text.null requestTopic = do
      hPutStrLn
        stderr
        "dispatcher loop disabled: daemon config has no inference request topic"
      forever (threadDelay 60_000_000)
  | otherwise = do
      managedContexts <- newMVar Set.empty
      managedUsers <- newMVar Set.empty
      manager <- newManager tlsManagerSettings
      forever $ do
        outcome <-
          try @SomeException
            ( discoverAndStartDispatchers
                transport
                runtimeMode
                requestTopic
                topicNamespace
                manager
                managedContexts
                managedUsers
                contextModelMap
                modelCatalog
            )
        case outcome of
          Right _ -> pure ()
          Left err ->
            hPutStrLn
              stderr
              ( "dispatcher topic discovery failed:\n"
                  <> displayException err
              )
        threadDelay (dispatcherTopicPollSeconds * 1_000_000)

discoverAndStartDispatchers ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  ConversationTopic.TopicNamespace ->
  Manager ->
  MVar (Set Text.Text) ->
  MVar (Set Text.Text) ->
  ContextModelMap ->
  [ModelDescriptor] ->
  IO ()
discoverAndStartDispatchers transport runtimeMode requestTopic topicNamespace manager managedContexts managedUsers contextModelMap modelCatalog = do
  adminBaseUrl <- requirePulsarAdminBaseUrl transport
  topics <- listNamespaceTopics manager adminBaseUrl topicNamespace
  forM_ topics $ \topicUrl -> do
    case parseConversationTopicUrl topicNamespace topicUrl of
      Just (userIdValue, contextIdValue) -> do
        startDispatcherWorkerIfNeeded
          transport
          runtimeMode
          requestTopic
          topicUrl
          userIdValue
          contextIdValue
          managedContexts
          contextModelMap
          modelCatalog
        startContextsMetadataWorkerIfNeeded
          transport
          topicNamespace
          userIdValue
          managedUsers
          contextModelMap
      Nothing -> pure ()

-- | List all non-partitioned topics in the supported demo namespace.
-- Pulsar admin v2 returns the topic URLs as
-- @persistent://<tenant>/<namespace>/<topic>@.
listNamespaceTopics ::
  Manager ->
  String ->
  ConversationTopic.TopicNamespace ->
  IO [Text.Text]
listNamespaceTopics manager adminBaseUrl ns = do
  let url =
        adminBaseUrl
          <> "/persistent/"
          <> Text.unpack (ConversationTopic.topicNamespaceTenant ns)
          <> "/"
          <> Text.unpack (ConversationTopic.topicNamespaceName ns)
  requestValue <- parseRequest url
  response <- httpLbs requestValue manager
  case statusCode (responseStatus response) of
    200 ->
      case eitherDecode (responseBody response) of
        Right topics -> pure topics
        Left decodeError ->
          ioError
            ( userError
                ( "failed to parse Pulsar namespace topic list for "
                    <> Text.unpack (ConversationTopic.topicNamespaceTenant ns)
                    <> "/"
                    <> Text.unpack (ConversationTopic.topicNamespaceName ns)
                    <> ":\n"
                    <> decodeError
                )
            )
    -- 404 means the namespace has no topics yet; treat as empty list so the
    -- dispatcher loop polls cleanly until the first conversation is created.
    404 -> pure []
    code ->
      ioError
        ( userError
            ( "failed to list Pulsar namespace topics (status "
                <> show code
                <> "):\n"
                <> lazyBodyToString (responseBody response)
            )
        )

-- | Extract @(UserId, ContextId)@ from a topic URL when the topic name
-- matches the supported @demo.conversation.<userId>.<contextId>@ shape.
-- Returns 'Nothing' for any other topic in the namespace.
parseConversationTopicUrl ::
  ConversationTopic.TopicNamespace ->
  Text.Text ->
  Maybe (Contracts.UserId, Contracts.ContextId)
parseConversationTopicUrl ns topicUrl = do
  let prefix =
        Text.concat
          [ "persistent://",
            ConversationTopic.topicNamespaceTenant ns,
            "/",
            ConversationTopic.topicNamespaceName ns,
            "/demo.conversation."
          ]
  remainder <- Text.stripPrefix prefix topicUrl
  case Text.splitOn "." remainder of
    [userIdValue, contextIdValue]
      | not (Text.null userIdValue) && not (Text.null contextIdValue) ->
          Just (Contracts.UserId userIdValue, Contracts.ContextId contextIdValue)
    _ -> Nothing

startDispatcherWorkerIfNeeded ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  Text.Text ->
  Contracts.UserId ->
  Contracts.ContextId ->
  MVar (Set Text.Text) ->
  ContextModelMap ->
  [ModelDescriptor] ->
  IO ()
startDispatcherWorkerIfNeeded transport runtimeMode requestTopic conversationTopic userIdValue contextIdValue managedContexts contextModelMap modelCatalog = do
  let Contracts.ContextId contextIdText = contextIdValue
  modifyMVar_ managedContexts $ \alreadyStarted ->
    if Set.member contextIdText alreadyStarted
      then pure alreadyStarted
      else do
        void
          ( forkIO
              ( runDispatcherForContext
                  transport
                  runtimeMode
                  requestTopic
                  conversationTopic
                  userIdValue
                  contextIdValue
                  contextModelMap
                  modelCatalog
                  `finally` modifyMVar_
                    managedContexts
                    (pure . Set.delete contextIdText)
              )
          )
        pure (Set.insert contextIdText alreadyStarted)

-- | Spawn a per-user worker that consumes the supported compacted
-- @demo.user.<userId>.contexts@ topic and writes @(contextId, modelId)@
-- pairs into the shared 'ContextModelMap'. Idempotent across discovery
-- cycles via 'managedUsers'.
startContextsMetadataWorkerIfNeeded ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  MVar (Set Text.Text) ->
  ContextModelMap ->
  IO ()
startContextsMetadataWorkerIfNeeded transport topicNamespace userIdValue managedUsers contextModelMap = do
  let Contracts.UserId userIdText = userIdValue
  modifyMVar_ managedUsers $ \alreadyStarted ->
    if Set.member userIdText alreadyStarted
      then pure alreadyStarted
      else do
        void
          ( forkIO
              ( runContextsMetadataConsumer
                  transport
                  topicNamespace
                  userIdValue
                  contextModelMap
                  `finally` modifyMVar_
                    managedUsers
                    (pure . Set.delete userIdText)
              )
          )
        pure (Set.insert userIdText alreadyStarted)

-- | The per-user compacted-topic reader. Each coordinator replica owns
-- its own process-local 'ContextModelMap', so every replica must replay
-- the context metadata stream independently. A shared Failover
-- subscription would populate only the active consumer's map while a
-- dispatcher on another replica could still receive conversation
-- events. The reader starts at the earliest broker offset on every
-- session so restart/reconnect replay remains idempotent.
runContextsMetadataConsumer ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  ContextModelMap ->
  IO ()
runContextsMetadataConsumer transport topicNamespace userIdValue contextModelMap = do
  let topicUrl = ConversationTopic.contextsMetadataTopicName topicNamespace userIdValue
      Contracts.UserId userIdText = userIdValue
  topicRef <- requireTopicRef topicUrl
  processLabel <- currentProcessLabel
  let readerName =
        "infernix-coordinator-context-model-map-"
          <> sanitizeTopic userIdText
          <> "-"
          <> sanitizeTopic processLabel
      readerPath =
        buildReaderSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          readerName
  retryCoordinatorStream transport topicUrl ("contexts metadata session for " <> topicUrl) $
    runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
      forever (handleContextsMetadataMessage contextModelMap connection)

handleContextsMetadataMessage ::
  ContextModelMap ->
  WebSockets.Connection ->
  IO ()
handleContextsMetadataMessage contextModelMap connection = do
  rawEnvelope <- receiveJsonFrame "contexts metadata message" connection
  envelope <- decodeJsonText "contexts metadata message" rawEnvelope
  handled <-
    try @SomeException
      ( do
          payloadBytes <- conversationPayloadBytes envelope
          case eitherDecode (Lazy.fromStrict payloadBytes) of
            Left decodeError ->
              hPutStrLn
                stderr
                ( "contexts metadata skipping undecodable event "
                    <> Text.unpack (envelopeMessageId envelope)
                    <> ": "
                    <> decodeError
                )
            Right event ->
              ContextModelMap.recordContextMetadataEvent contextModelMap event
      )
  case handled of
    Right _ -> sendAck connection (envelopeMessageId envelope)
    Left err -> do
      sendNegativeAck connection (envelopeMessageId envelope)
      hPutStrLn
        stderr
        ( "contexts metadata message handling failed:\n"
            <> displayException err
        )

-- | The per-context dispatcher worker. Maintains 'ReducerState' across
-- subscription sessions; on Failover handoff the surviving replica
-- replays from the broker's earliest position and folds back up to
-- the cursor. Producer-side dedup catches any duplicate dispatch from
-- the recovered replica.
runDispatcherForContext ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  Text.Text ->
  Contracts.UserId ->
  Contracts.ContextId ->
  ContextModelMap ->
  [ModelDescriptor] ->
  IO ()
runDispatcherForContext transport runtimeMode requestTopic conversationTopic userIdValue contextIdValue contextModelMap modelCatalog = do
  reducerStateRef <- newIORef (initialReducerState contextIdValue)
  processLabel <- currentProcessLabel
  let subscriptionName = Dispatch.dispatcherSubscriptionName contextIdValue
      consumerName = PulsarFailover.failoverConsumerName subscriptionName processLabel
  topicRef <- requireTopicRef conversationTopic
  let consumerPath =
        buildFailoverConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          (Text.unpack subscriptionName)
          (Text.unpack consumerName)
  retryCoordinatorStream transport conversationTopic ("dispatcher session for " <> conversationTopic) $
    runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
      forever
        ( handleDispatcherMessage
            transport
            runtimeMode
            requestTopic
            userIdValue
            contextIdValue
            reducerStateRef
            contextModelMap
            modelCatalog
            connection
        )

handleDispatcherMessage ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  Contracts.UserId ->
  Contracts.ContextId ->
  IORef ReducerState ->
  ContextModelMap ->
  [ModelDescriptor] ->
  WebSockets.Connection ->
  IO ()
handleDispatcherMessage transport runtimeMode requestTopic userIdValue contextIdValue reducerStateRef contextModelMap modelCatalog connection = do
  rawEnvelope <- receiveJsonFrame "Pulsar dispatcher message" connection
  envelope <- decodeJsonText "Pulsar dispatcher message" rawEnvelope
  handled <-
    try @SomeException
      ( do
          eventBytes <- conversationPayloadBytes envelope
          case eitherDecode (Lazy.fromStrict eventBytes) of
            Left decodeError ->
              hPutStrLn
                stderr
                ( "dispatcher skipping undecodable conversation event "
                    <> Text.unpack (envelopeMessageId envelope)
                    <> ": "
                    <> decodeError
                )
            Right conversationEvent -> do
              let messageId = Contracts.MessageId (envelopeMessageId envelope)
                  conversationMessage =
                    Contracts.ConversationMessage messageId conversationEvent
              currentState <- readIORef reducerStateRef
              case stepReducer currentState conversationMessage of
                StepDropped unchanged ->
                  writeIORef reducerStateRef unchanged
                StepAdvanced advancedState _patch ->
                  case Dispatch.buildDispatchDecision userIdValue advancedState of
                    Dispatch.DispatchNoOp ->
                      writeIORef reducerStateRef advancedState
                    Dispatch.DispatchPrompt inferenceEnvelope -> do
                      modelIdValue <- resolveContextModelIdForDispatch contextModelMap contextIdValue
                      publishDispatchedInferenceRequest
                        transport
                        runtimeMode
                        requestTopic
                        modelCatalog
                        modelIdValue
                        inferenceEnvelope
                      writeIORef reducerStateRef advancedState
      )
  case handled of
    Right _ -> sendAck connection (envelopeMessageId envelope)
    Left err -> do
      sendNegativeAck connection (envelopeMessageId envelope)
      hPutStrLn
        stderr
        ( "dispatcher message handling failed:\n"
            <> displayException err
        )

resolveContextModelIdForDispatch :: ContextModelMap -> Contracts.ContextId -> IO Text.Text
resolveContextModelIdForDispatch contextModelMap contextIdValue@(Contracts.ContextId contextIdText) =
  go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = do
          hPutStrLn
            stderr
            ( "dispatcher model id unresolved for context "
                <> Text.unpack contextIdText
                <> " after waiting for contexts metadata; publishing typed empty-model rejection"
            )
          pure Text.empty
      | otherwise = do
          maybeModelId <- ContextModelMap.lookupModelId contextModelMap contextIdValue
          case maybeModelId of
            Just modelIdValue
              | not (Text.null modelIdValue) -> pure modelIdValue
            _ -> do
              threadDelay 500000
              go (remainingAttempts - 1)

conversationPayloadBytes :: PulsarEnvelope -> IO ByteString.ByteString
conversationPayloadBytes envelope =
  case Base64.decode (TextEncoding.encodeUtf8 (envelopePayload envelope)) of
    Right raw -> pure raw
    Left err ->
      ioError
        ( userError
            ( "failed to decode base64 conversation event payload for message "
                <> Text.unpack (envelopeMessageId envelope)
                <> ":\n"
                <> err
            )
        )

-- | Publish a dispatcher-built envelope to the substrate's inference
-- request topic. Producer name is stable per @ContextId@ so the broker
-- dedup gate sees a single producer scope per per-context queue;
-- sequence id is derived from the dispatcher envelope's
-- @userPromptMessageId@ so a recovered replica that re-dispatches
-- collides with the original publish.
publishDispatchedInferenceRequest ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  [ModelDescriptor] ->
  Text.Text ->
  Dispatch.InferenceRequestEnvelope ->
  IO ()
publishDispatchedInferenceRequest transport runtimeMode requestTopic modelCatalog resolvedModelId env = do
  let Contracts.ContextId contextIdText = Dispatch.inferenceContextId env
      Contracts.UserId userIdText = Dispatch.inferenceUserId env
      Contracts.MessageId promptMessageIdText = Dispatch.inferenceUserPromptMessageId env
      Contracts.ClientIdempotencyKey idempotencyKey = Dispatch.inferenceClientIdempotencyKey env
      protoPayload :: ProtoInference.InferenceRequest
      protoPayload =
        set (field @"requestId") promptMessageIdText
          . set (field @"requestModelId") resolvedModelId
          . set (field @"inputText") (Dispatch.inferencePromptText env)
          . set (field @"inputObjectRef") (fromMaybe "" (dispatchedInputObjectRef modelCatalog resolvedModelId env))
          . set (field @"runtimeMode") (runtimeModeId runtimeMode)
          . set (field @"userId") userIdText
          . set (field @"contextId") contextIdText
          . set (field @"userPromptMessageId") promptMessageIdText
          . set (field @"clientIdempotencyKey") idempotencyKey
          . set
            (field @"conversationLogOffset")
            (fromIntegral (Dispatch.inferenceConversationLogOffset env))
          . set (field @"prefixHash") (Dispatch.inferencePrefixHash env)
          . set (field @"causalRef") (Dispatch.inferenceCausalRef env)
          $ defMessage
      options =
        (defaultPublishOptions ("dispatcher-" <> contextIdText))
          { publishSequenceId = parseMessageIdToSequenceId promptMessageIdText
          }
  publishTopicPayload
    transport
    requestTopic
    options
    promptMessageIdText
    (encodeMessage protoPayload)

dispatchedInputObjectRef :: [ModelDescriptor] -> Text.Text -> Dispatch.InferenceRequestEnvelope -> Maybe Text.Text
dispatchedInputObjectRef modelCatalog resolvedModelId env = do
  model <-
    listToMaybe
      [ candidate
      | candidate <- modelCatalog,
        modelId candidate == resolvedModelId
      ]
  if modelRequiresInputObject model
    then renderDispatchedObjectRef <$> listToMaybe (Dispatch.inferencePromptUserUploads env)
    else Nothing

renderDispatchedObjectRef :: Contracts.ObjectRef -> Text.Text
renderDispatchedObjectRef objectRef =
  Contracts.objectBucket objectRef <> "/" <> Contracts.objectKey objectRef

-- | Phase 7 Sprint 7.7 / 7.14 model-bootstrap runtime loop. The
-- coordinator subscribes to @infernix/system/model.bootstrap.request@
-- with a Failover subscription (exactly one coordinator replica is
-- active at a time; on crash the broker promotes a surviving replica
-- and redelivers any unacked request). For each request:
--
-- 1. Re-check the upstream @.ready@ sentinel object in MinIO so
--    duplicate work after Failover handoff is a no-op (the helper
--    'sentinelExistsInMinio' returns @True@ when the object is
--    already present; we skip straight to publishing the ready event).
-- 2. Materialize the upstream @downloadUrl@ carried on the request
--    envelope (this is the only point in the supported daemon
--    topology that reaches the public internet). Hugging Face model
--    repository URLs are downloaded as snapshots; non-repository URLs
--    keep the single-payload fallback.
-- 3. @PUT@ the materialized model files to MinIO under
--    @infernix-models/<modelId>/...@ via S3 credentials minted from
--    mounted @ClusterConfig.minio@ wiring and
--    @SecretsConfig.minio.credentialsPath@ credentials.
-- 4. @PUT@ the @.ready@ sentinel last so partial uploads are not
--    visible to engines (the engine helper waits on this sentinel).
-- 5. Publish a 'ModelBootstrapReadyEvent' on the matching ready topic
--    and ack the original request.
--
-- Producer-side dedup on the request topic is scoped to the request
-- attempt, while the message key remains @modelId@. Exact replays of
-- the same request collapse; later recovery attempts can still enqueue
-- work if a previous attempt never produced readiness.
runModelBootstrapLoop ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  IO ()
runModelBootstrapLoop transport systemNamespace = do
  let requestTopic =
        ConversationTopic.modelBootstrapRequestTopicName systemNamespace
  topicRef <- requireTopicRef requestTopic
  processLabel <- currentProcessLabel
  let consumerName =
        Text.unpack
          ( PulsarFailover.failoverConsumerName
              BootstrapModels.bootstrapSubscriptionName
              processLabel
          )
      consumerPath =
        buildFailoverConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          (Text.unpack BootstrapModels.bootstrapSubscriptionName)
          consumerName
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
            forever (handleBootstrapMessage transport systemNamespace connection)
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "model-bootstrap session for "
              <> Text.unpack requestTopic
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

handleBootstrapMessage ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  WebSockets.Connection ->
  IO ()
handleBootstrapMessage transport systemNamespace connection = do
  rawEnvelope <- receiveJsonFrame "Pulsar bootstrap message" connection
  envelope <- decodeJsonText "Pulsar bootstrap message" rawEnvelope
  handled <-
    try @SomeException
      ( do
          payloadBytes <- bootstrapPayloadBytes envelope
          case eitherDecodeStrict' payloadBytes of
            Left err ->
              hPutStrLn
                stderr
                ( "model-bootstrap skipping undecodable request "
                    <> Text.unpack (envelopeMessageId envelope)
                    <> ": "
                    <> err
                )
            Right request -> processBootstrapRequest transport systemNamespace request
      )
  case handled of
    Right _ -> sendAck connection (envelopeMessageId envelope)
    Left err -> do
      sendNegativeAck connection (envelopeMessageId envelope)
      hPutStrLn
        stderr
        ( "model-bootstrap message handling failed:\n"
            <> displayException err
        )

bootstrapPayloadBytes :: PulsarEnvelope -> IO ByteString.ByteString
bootstrapPayloadBytes envelope =
  case Base64.decode (TextEncoding.encodeUtf8 (envelopePayload envelope)) of
    Right raw -> pure raw
    Left err ->
      ioError
        ( userError
            ( "failed to decode base64 model-bootstrap payload for message "
                <> Text.unpack (envelopeMessageId envelope)
                <> ":\n"
                <> err
            )
        )

processBootstrapRequest ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  BootstrapModels.ModelBootstrapRequest ->
  IO ()
processBootstrapRequest transport systemNamespace request = do
  presignedConfigResult <- loadBootstrapPresignedConfig
  case presignedConfigResult of
    Left configError ->
      hPutStrLn
        stderr
        ( "model-bootstrap unable to load MinIO credentials: "
            <> configError
        )
    Right presigned -> do
      let modelId = BootstrapModels.bootstrapRequestModelId request
          payloadObject =
            Contracts.ObjectRef
              { Contracts.objectBucket = "infernix-models",
                Contracts.objectKey = modelId <> "/payload"
              }
          sentinelObject =
            Contracts.ObjectRef
              { Contracts.objectBucket = "infernix-models",
                Contracts.objectKey =
                  modelId <> "/" <> BootstrapModels.readySentinelFilename
              }
      manager <- newManager tlsManagerSettings
      now <- getCurrentTime
      sentinelPresent <- minioObjectExists presigned manager sentinelObject
      if sentinelPresent
        then publishBootstrapReadyEvent transport systemNamespace request
        else do
          let downloadUrl = BootstrapModels.bootstrapRequestDownloadUrl request
          if isPackageBackedNativeModel modelId
            then putMinioObject presigned manager now sentinelObject "ready\n"
            else
              if isHuggingFaceModelRepoUrl downloadUrl || isMultiFileModelRepoUrl downloadUrl
                then runModelBootstrapSnapshotHelper presigned request
                else withDownloadedUpstreamModel manager downloadUrl $ \downloadedPath -> do
                  putMinioObjectFile presigned manager now payloadObject downloadedPath
                  putMinioObject presigned manager now sentinelObject "ready\n"
          publishBootstrapReadyEvent transport systemNamespace request

-- | Phase 8 Sprint 8.5: eager model-cache staging. On coordinator startup,
-- stage every model listed in the mounted substrate config so no inference
-- ever races a cold cache. Reuses the idempotent
-- download/upload/@.ready@-sentinel logic ('processBootstrapRequest'), which
-- short-circuits when the sentinel is already present. The lazy
-- 'runModelBootstrapLoop' remains the on-demand fallback. Each model is
-- staged independently: a failure is logged and does not abort the sweep, so
-- the remaining models still stage (the coordinator surfaces per-model
-- progress and the @cluster up@ warm-model-cache barrier waits on the
-- sentinels).
sweepEagerModelCache ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  DemoConfig ->
  IO ()
sweepEagerModelCache transport systemNamespace demoConfig = do
  let modelDescriptors = models demoConfig
  putStrLn ("serviceEagerModelCacheCount: " <> show (length modelDescriptors))
  forM_ modelDescriptors $ \model -> do
    request <- modelBootstrapRequestFor model
    outcome <- try @SomeException (processBootstrapRequest transport systemNamespace request)
    case outcome of
      Right _ -> putStrLn ("serviceEagerModelCacheStaged: " <> Text.unpack (modelId model))
      Left err ->
        hPutStrLn
          stderr
          ( "eager model-cache staging failed for "
              <> Text.unpack (modelId model)
              <> " (the lazy per-inference fallback still covers this model):\n"
              <> displayException err
          )
  putStrLn "serviceEagerModelCacheSweep: complete"

-- | Phase 8 Sprint 8.5: the @cluster up@ warm-model-cache barrier. Polls
-- MinIO at a host-reachable endpoint for each configured model's @.ready@
-- sentinel, using a progress-based deadline: the wait continues as long as
-- new sentinels keep appearing, and only gives up after a stall window with
-- no new readiness (or an absolute safety ceiling). Returns the model ids
-- still not staged (empty = every configured model is warm). The caller
-- treats a non-empty result as a warning rather than a hard failure: the
-- coordinator's forked eager sweep plus the lazy per-inference fallback still
-- complete staging.
waitForEagerModelCacheReady :: String -> [Text.Text] -> (String -> IO ()) -> IO [Text.Text]
waitForEagerModelCacheReady minioBaseEndpoint modelIds logProgress = do
  let (scheme, hostPort) = splitMinioEndpoint (Text.pack minioBaseEndpoint)
      presigned =
        Presigned.PresignedUrlConfig
          { Presigned.presignedScheme = scheme,
            Presigned.presignedEndpoint = hostPort,
            Presigned.presignedPathPrefix = "",
            Presigned.presignedRegion = "us-east-1",
            Presigned.presignedAccessKeyId = "minioadmin",
            Presigned.presignedSecretAccessKey = "minioadmin123",
            Presigned.presignedExpirySeconds = 900
          }
  manager <- newManager tlsManagerSettings
  let pollIntervalSeconds = 5
      stallLimitSeconds = 600
      absoluteMaxSeconds = modelBootstrapReadyWaitMaxSeconds
      sentinelReady modelIdValue = do
        let sentinelObject =
              Contracts.ObjectRef
                { Contracts.objectBucket = "infernix-models",
                  Contracts.objectKey = modelIdValue <> "/" <> BootstrapModels.readySentinelFilename
                }
        try @SomeException (minioObjectExists presigned manager sentinelObject)
          >>= either (const (pure False)) pure
      go elapsedSeconds stallSeconds lastReadyCount = do
        pending <- filterM (fmap not . sentinelReady) modelIds
        let readyCount = length modelIds - length pending
        if null pending
          then pure []
          else
            if elapsedSeconds >= absoluteMaxSeconds
              then pure pending
              else
                if readyCount > lastReadyCount
                  then do
                    logProgress (show readyCount <> "/" <> show (length modelIds) <> " models staged")
                    threadDelay (pollIntervalSeconds * 1000000)
                    go (elapsedSeconds + pollIntervalSeconds) 0 readyCount
                  else
                    if stallSeconds >= stallLimitSeconds
                      then pure pending
                      else do
                        threadDelay (pollIntervalSeconds * 1000000)
                        go (elapsedSeconds + pollIntervalSeconds) (stallSeconds + pollIntervalSeconds) readyCount
  go 0 0 (-1)

-- | Multi-file model sources (e.g. Open-Unmix `umxhq`, which is four per-target
-- Zenodo state dicts, not one file or a HuggingFace repo) are staged through the
-- snapshot helper, which downloads each file and mirrors the directory into
-- `infernix-models/<modelId>/`.
isMultiFileModelRepoUrl :: Text.Text -> Bool
isMultiFileModelRepoUrl rawUrl =
  "zenodo.org/records/3370489" `Text.isInfixOf` rawUrl
    || "github.com/kunato/mt3-pytorch" `Text.isInfixOf` rawUrl

isPackageBackedNativeModel :: Text.Text -> Bool
isPackageBackedNativeModel modelId =
  modelId `elem` ["audio-basic-pitch-coreml", "tool-audiveris"]

isHuggingFaceModelRepoUrl :: Text.Text -> Bool
isHuggingFaceModelRepoUrl rawUrl =
  ("https://huggingface.co/" `Text.isPrefixOf` rawUrl || "http://huggingface.co/" `Text.isPrefixOf` rawUrl)
    && not ("/resolve/" `Text.isInfixOf` rawUrl)
    && not ("/blob/" `Text.isInfixOf` rawUrl)

runModelBootstrapSnapshotHelper ::
  Presigned.PresignedUrlConfig ->
  BootstrapModels.ModelBootstrapRequest ->
  IO ()
runModelBootstrapSnapshotHelper presigned request = do
  paths <- discoverPaths
  poetryExecutable <- ensurePoetryExecutable paths
  let minioEndpoint =
        Presigned.presignedScheme presigned
          <> "://"
          <> Presigned.presignedEndpoint presigned
      args =
        [ "--directory",
          "python",
          "run",
          "bootstrap-model-snapshot",
          "--model-id",
          Text.unpack (BootstrapModels.bootstrapRequestModelId request),
          "--download-url",
          Text.unpack (BootstrapModels.bootstrapRequestDownloadUrl request),
          "--minio-endpoint",
          Text.unpack minioEndpoint,
          "--minio-access-key",
          Text.unpack (Presigned.presignedAccessKeyId presigned),
          "--minio-secret-key",
          Text.unpack (Presigned.presignedSecretAccessKey presigned),
          "--minio-region",
          Text.unpack (Presigned.presignedRegion presigned),
          "--models-bucket",
          "infernix-models"
        ]
  (exitCode, stdoutOutput, stderrOutput) <- readProcessWithExitCode poetryExecutable args ""
  case exitCode of
    ExitSuccess -> pure ()
    _ ->
      ioError
        ( userError
            ( "model-bootstrap snapshot helper failed for "
                <> Text.unpack (BootstrapModels.bootstrapRequestModelId request)
                <> ":\n"
                <> stdoutOutput
                <> stderrOutput
            )
        )

publishBootstrapReadyEvent ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  BootstrapModels.ModelBootstrapRequest ->
  IO ()
publishBootstrapReadyEvent transport systemNamespace request = do
  now <- getCurrentTime
  let modelId = BootstrapModels.bootstrapRequestModelId request
      readyTopic = BootstrapModels.bootstrapReadyTopicFor (qualifiedReadyTopicPrefix systemNamespace) modelId
      event =
        BootstrapModels.ModelBootstrapReadyEvent
          { BootstrapModels.readyEventModelId = modelId,
            BootstrapModels.readyEventReadyAtIso8601 =
              Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now)
          }
      dedupKey = BootstrapModels.readyEventDedupKey event
      options =
        (defaultPublishOptions ("infernix-model-bootstrap-" <> dedupKey))
          { publishMessageKey = Just modelId,
            publishSequenceId = Just (stableSequenceId dedupKey)
          }
  publishTopicPayload
    transport
    readyTopic
    options
    modelId
    (Lazy.toStrict (encode event))

qualifiedReadyTopicPrefix :: ConversationTopic.TopicNamespace -> Text.Text
qualifiedReadyTopicPrefix ns =
  Text.concat
    [ "persistent://",
      ConversationTopic.topicNamespaceTenant ns,
      "/",
      ConversationTopic.topicNamespaceName ns
    ]

withDownloadedUpstreamModel :: Manager -> Text.Text -> (FilePath -> IO a) -> IO a
withDownloadedUpstreamModel manager urlText action = do
  temporaryDirectory <- getTemporaryDirectory
  (temporaryPath, temporaryHandle) <- openBinaryTempFile temporaryDirectory "infernix-model-payload.tmp"
  let cleanup = do
        ignoreCleanupError (hClose temporaryHandle)
        ignoreCleanupError (removeFile temporaryPath)
  ( do
      downloadUpstreamModelToFile manager urlText temporaryHandle
      hClose temporaryHandle
      action temporaryPath
    )
    `finally` cleanup

downloadUpstreamModelToFile :: Manager -> Text.Text -> Handle -> IO ()
downloadUpstreamModelToFile manager urlText outputHandle = do
  request <- parseRequest (Text.unpack urlText)
  firstNonSpaceByteRef <- newIORef Nothing
  withResponse request manager $ \response -> do
    let code = statusCode (responseStatus response)
    unless (code == 200) $
      ioError
        ( userError
            ( "upstream model download "
                <> Text.unpack urlText
                <> " returned HTTP "
                <> show code
            )
        )
    let loop = do
          chunk <- brRead (responseBody response)
          if ByteString.null chunk
            then pure ()
            else do
              recordFirstNonSpaceByte firstNonSpaceByteRef chunk
              ByteString.hPut outputHandle chunk
              loop
    loop
  firstNonSpaceByte <- readIORef firstNonSpaceByteRef
  when (firstNonSpaceByteLooksLikeHtml firstNonSpaceByte) $
    ioError
      ( userError
          ( "upstream model download "
              <> Text.unpack urlText
              <> " returned non-weight content: the response body begins with markup or is "
              <> "empty, not a binary single-file model weight; the download URL likely "
              <> "points at a repository landing page rather than a direct weight artifact"
          )
      )

recordFirstNonSpaceByte :: IORef (Maybe Word8) -> ByteString.ByteString -> IO ()
recordFirstNonSpaceByte firstNonSpaceByteRef chunk = do
  current <- readIORef firstNonSpaceByteRef
  case current <|> bodyFirstNonSpaceByte chunk of
    Just firstByte -> writeIORef firstNonSpaceByteRef (Just firstByte)
    Nothing -> pure ()

bodyFirstNonSpaceByte :: ByteString.ByteString -> Maybe Word8
bodyFirstNonSpaceByte body =
  fst <$> ByteString.uncons (ByteString.dropWhile isAsciiSpace body)

isAsciiSpace :: Word8 -> Bool
isAsciiSpace w = w == 32 || w == 9 || w == 10 || w == 13

-- | Reopened Phase 4 Sprint 4.21 realness weight-staging guard, retained for
-- the streaming bootstrap path: a real single-file model weight (ONNX, GGUF,
-- safetensors, ...) is binary and never begins with @<@.
firstNonSpaceByteLooksLikeHtml :: Maybe Word8 -> Bool
firstNonSpaceByteLooksLikeHtml firstNonSpaceByte =
  firstNonSpaceByte == Just 60 || isNothing firstNonSpaceByte

ignoreCleanupError :: IO () -> IO ()
ignoreCleanupError action =
  void (try @SomeException action)

minioObjectExists ::
  Presigned.PresignedUrlConfig ->
  Manager ->
  Contracts.ObjectRef ->
  IO Bool
minioObjectExists presigned manager objectRef = do
  now <- getCurrentTime
  let signedUrl =
        Presigned.unPresignedUrl
          (Presigned.presignedGetUrl presigned now objectRef)
  request <- parseRequest (Text.unpack signedUrl)
  let headRequest = request {method = "HEAD"}
  response <- httpLbs headRequest manager
  pure (statusCode (responseStatus response) == 200)

putMinioObject ::
  Presigned.PresignedUrlConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  ByteString.ByteString ->
  IO ()
putMinioObject presigned manager now objectRef payload = do
  let signedUrl =
        Presigned.unPresignedUrl
          (Presigned.presignedPutUrl presigned now objectRef)
  request <- parseRequest (Text.unpack signedUrl)
  let putRequest =
        request
          { method = "PUT",
            requestBody = RequestBodyLBS (Lazy.fromStrict payload)
          }
  response <- httpLbs putRequest manager
  let code = statusCode (responseStatus response)
  unless (code `elem` [200, 204]) $
    ioError
      ( userError
          ( "MinIO PUT for "
              <> Text.unpack (Contracts.objectBucket objectRef)
              <> "/"
              <> Text.unpack (Contracts.objectKey objectRef)
              <> " returned HTTP "
              <> show code
          )
      )

putMinioObjectFile ::
  Presigned.PresignedUrlConfig ->
  Manager ->
  UTCTime ->
  Contracts.ObjectRef ->
  FilePath ->
  IO ()
putMinioObjectFile presigned manager now objectRef payloadPath =
  withBinaryFile payloadPath ReadMode $ \payloadHandle -> do
    payloadSize <- hFileSize payloadHandle
    let signedUrl =
          Presigned.unPresignedUrl
            (Presigned.presignedPutUrl presigned now objectRef)
    request <- parseRequest (Text.unpack signedUrl)
    let popper = ByteString.hGetSome payloadHandle 65536
        putRequest =
          request
            { method = "PUT",
              requestBody =
                RequestBodyStream
                  (fromIntegral payloadSize)
                  (\needsPopper -> needsPopper popper)
            }
    response <- httpLbs putRequest manager
    let code = statusCode (responseStatus response)
    unless (code `elem` [200, 204]) $
      ioError
        ( userError
            ( "MinIO PUT for "
                <> Text.unpack (Contracts.objectBucket objectRef)
                <> "/"
                <> Text.unpack (Contracts.objectKey objectRef)
                <> " returned HTTP "
                <> show code
            )
        )

-- | Phase 7 Sprint 7.17: @INFERNIX_MINIO_*@ env reads retired. The
-- supported flow reads non-credential wiring (endpoint, region,
-- presign-expiry) from the mounted 'ClusterConfig' and credentials
-- (access key, secret key) from the file path declared by the mounted
-- 'SecretsConfig.minio.credentialsPath'.
loadBootstrapPresignedConfig :: IO (Either String Presigned.PresignedUrlConfig)
loadBootstrapPresignedConfig = do
  clusterExists <- doesFileExist Cluster.defaultClusterConfigMountPath
  secretsExists <- doesFileExist Secrets.defaultClusterSecretsMountPath
  if not (clusterExists && secretsExists)
    then
      pure
        ( Left
            ( "model-bootstrap requires the cluster ConfigMap at "
                <> Cluster.defaultClusterConfigMountPath
                <> " and the secrets Secret at "
                <> Secrets.defaultClusterSecretsMountPath
                <> "; the coordinator pod is the supported caller for this code path"
            )
        )
    else do
      clusterConfig <- Cluster.decodeClusterConfigFile Cluster.defaultClusterConfigMountPath
      secretsConfig <- Secrets.decodeSecretsConfigFile Secrets.defaultClusterSecretsMountPath
      minioCreds <- Secrets.readMinioCredentials (Secrets.secretsMinio secretsConfig)
      let minio = Cluster.clusterMinio clusterConfig
          (scheme, hostPort) = splitMinioEndpoint (Cluster.minioEndpoint minio)
      pure
        ( Right
            Presigned.PresignedUrlConfig
              { Presigned.presignedScheme = scheme,
                Presigned.presignedEndpoint = hostPort,
                Presigned.presignedPathPrefix = "",
                Presigned.presignedRegion = Cluster.minioRegion minio,
                Presigned.presignedAccessKeyId = Secrets.minioAccessKey minioCreds,
                Presigned.presignedSecretAccessKey = Secrets.minioSecretKey minioCreds,
                Presigned.presignedExpirySeconds = fromIntegral (Cluster.minioPresignExpirySeconds minio)
              }
        )

splitMinioEndpoint :: Text.Text -> (Text.Text, Text.Text)
splitMinioEndpoint raw =
  case Text.stripPrefix "https://" raw of
    Just hostPort -> ("https", hostPort)
    Nothing ->
      case Text.stripPrefix "http://" raw of
        Just hostPort -> ("http", hostPort)
        Nothing -> ("http", raw)

-- | Build a Pulsar WebSocket consumer URL with a @Failover@
-- subscription. Differs from 'buildConsumerSocketPath' which uses
-- @Shared@; Failover is the right semantic for the result-bridge so
-- exactly one coordinator replica processes a given message at a
-- time.
buildFailoverConsumerSocketPath ::
  PulsarWebSocketBase ->
  TopicRef ->
  String ->
  String ->
  String
buildFailoverConsumerSocketPath websocketBase topicRef subscriptionName consumerName =
  buildSocketPath
    websocketBase
    ("consumer/" <> renderTopicPath topicRef <> "/" <> subscriptionName)
    [ ("subscriptionType", "Failover"),
      ("subscriptionInitialPosition", "Earliest"),
      ("receiverQueueSize", "1"),
      ("consumerName", consumerName)
    ]

readPublishedInferenceResultViaPulsar :: PulsarTransport -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
readPublishedInferenceResultViaPulsar transport topicValue wantedRequestId = do
  topicRef <- requireTopicRef topicValue
  let readerName = "infernix-read-" <> sanitizeTopic wantedRequestId
      readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
    readMatchingResult connection
  where
    readMatchingResult connection = do
      maybeRawEnvelope <- timeout 200000 (receiveJsonFrame "Pulsar reader message" connection)
      case maybeRawEnvelope of
        Nothing -> pure Nothing
        Just rawEnvelope -> do
          envelope <- decodeJsonText "Pulsar reader message" rawEnvelope
          sendAck connection (envelopeMessageId envelope)
          protoResult <- decodeEnvelopePayload "inference result" envelope
          case protoResultToDomain protoResult of
            Just resultValue
              | requestId resultValue == wantedRequestId ->
                  pure (Just resultValue)
            _ ->
              readMatchingResult connection

-- | Phase 7 Sprint 7.12 — engine-side rejection when the dispatcher
-- could not resolve the per-context model id (the @ContextCreated@
-- event has not been observed yet, or the SPA flow that pins model id
-- is not wired). The engine produces a typed failed result instead of
-- silently dispatching to a generic engine path. The result-bridge
-- writes this back to the conversation log so the SPA renders the
-- typed error in the Chat surface.
emptyModelIdRejectionResult ::
  RuntimeMode ->
  ProtoInference.InferenceRequest ->
  InferenceResult
emptyModelIdRejectionResult runtimeMode protoRequest =
  let envelopeUserId = view ProtoInferenceFields.userId protoRequest
      envelopeContextId = view ProtoInferenceFields.contextId protoRequest
      envelopeCausalRef = view ProtoInferenceFields.userPromptMessageId protoRequest
   in InferenceResult
        { requestId = view ProtoInferenceFields.requestId protoRequest,
          resultModelId = "",
          resultMatrixRowId = "",
          resultRuntimeMode = runtimeMode,
          resultSelectedEngine = "",
          status = "failed",
          payload =
            ResultPayload
              { inlineOutput =
                  Just
                    "request rejected: model id was not resolved for this context (the SPA's ContextCreated event has not been observed yet, or the coordinator's contexts-metadata consumer has not caught up)",
                objectRef = Nothing
              },
          createdAt = emptyModelIdRejectionTimestamp,
          resultUserId = envelopeUserId,
          resultContextId = envelopeContextId,
          resultCausalRef = envelopeCausalRef
        }

-- | The empty-model-id rejection path returns a deterministic
-- timestamp so the rejection result is byte-identical across duplicate
-- redeliveries. Pulsar producer dedup on the result topic collapses
-- those duplicates.
emptyModelIdRejectionTimestamp :: UTCTime
emptyModelIdRejectionTimestamp =
  case parseTimeM True defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" "1970-01-01T00:00:00Z" of
    Just timestamp -> timestamp
    Nothing -> error "internal: failed to parse fixed epoch timestamp"

publishedResultFromRequest ::
  Maybe PulsarTransport ->
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  Maybe KVCache.EngineKVCache ->
  ProtoInference.InferenceRequest ->
  IO InferenceResult
publishedResultFromRequest maybeTransport paths runtimeMode overrides maybeEngineKVCache protoRequest = do
  domainResult <-
    executeInferenceWithModelBootstrapRetry
      maybeTransport
      paths
      runtimeMode
      overrides
      maybeEngineKVCache
      (kvCacheRequestFromProto protoRequest)
      (protoRequestToDomain protoRequest)
  now <- getCurrentTime
  let envelopeUserId = view ProtoInferenceFields.userId protoRequest
      envelopeContextId = view ProtoInferenceFields.contextId protoRequest
      envelopeCausalRef = view ProtoInferenceFields.userPromptMessageId protoRequest
  case domainResult of
    Right resultValue ->
      pure
        resultValue
          { requestId = view ProtoInferenceFields.requestId protoRequest,
            -- Phase 7 Sprint 7.8: forward the durable-context routing
            -- fields from the request envelope into the result so the
            -- coordinator's result-bridge can compute the destination
            -- conversation topic without consulting a separate cache.
            resultUserId = envelopeUserId,
            resultContextId = envelopeContextId,
            resultCausalRef = envelopeCausalRef
          }
    Left errorValue ->
      pure
        InferenceResult
          { requestId = view ProtoInferenceFields.requestId protoRequest,
            resultModelId = view ProtoInferenceFields.requestModelId protoRequest,
            resultMatrixRowId = "",
            resultRuntimeMode = runtimeMode,
            resultSelectedEngine = "",
            status = "failed",
            payload = ResultPayload {inlineOutput = Just (message errorValue), objectRef = Nothing},
            createdAt = now,
            resultUserId = envelopeUserId,
            resultContextId = envelopeContextId,
            resultCausalRef = envelopeCausalRef
          }

executeInferenceWithModelBootstrapRetry ::
  Maybe PulsarTransport ->
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  Maybe KVCache.EngineKVCache ->
  Maybe KVCache.KVCacheRequest ->
  InferenceRequest ->
  IO (Either ErrorResponse InferenceResult)
executeInferenceWithModelBootstrapRetry maybeTransport paths runtimeMode overrides maybeEngineKVCache maybeKVCacheRequest requestValue = do
  firstResult <- runOnce
  case firstResult of
    Left errorValue
      | modelCacheBootstrapRetryableError errorValue ->
          case maybeTransport of
            Nothing -> pure firstResult
            Just transport -> bootstrapAndRetry transport errorValue
    _ -> pure firstResult
  where
    runOnce =
      executeInferenceWithKVCache
        paths
        runtimeMode
        overrides
        maybeEngineKVCache
        maybeKVCacheRequest
        requestValue
    bootstrapAndRetry transport errorValue =
      case findModel runtimeMode (requestModelId requestValue) of
        Nothing -> pure (Left errorValue)
        Just model -> do
          request <- modelBootstrapRequestFor model
          publishModelBootstrapRequestViaTransport transport request
          ready <-
            waitForModelBootstrapReady
              transport
              (BootstrapModels.bootstrapRequestModelId request)
          if ready
            then runOnce
            else
              pure
                ( Left
                    ErrorResponse
                      { errorCode = "model_cache_bootstrap_timeout",
                        message =
                          "Timed out waiting for model bootstrap readiness for "
                            <> BootstrapModels.bootstrapRequestModelId request
                            <> " after publishing a bootstrap request."
                      }
                )

modelBootstrapRequestFor :: ModelDescriptor -> IO BootstrapModels.ModelBootstrapRequest
modelBootstrapRequestFor model = do
  now <- getCurrentTime
  pure
    BootstrapModels.ModelBootstrapRequest
      { BootstrapModels.bootstrapRequestModelId = modelId model,
        BootstrapModels.bootstrapRequestDownloadUrl = downloadUrl model,
        BootstrapModels.bootstrapRequestRequestedAtIso8601 =
          Text.pack (formatTime defaultTimeLocale "%Y-%m-%dT%H:%M:%SZ" now)
      }

modelBootstrapReadyPollMicros :: Int
modelBootstrapReadyPollMicros = 250000

-- | Engine-side ceiling for how long an engine waits on the coordinator's
-- lazy model bootstrap (Hugging Face download -> MinIO upload -> ready event)
-- after publishing a bootstrap request. The coordinator's `snapshot_download`
-- has no hard wall, so this is the effective envelope. 60 min accommodates the
-- largest catalog repos on a constrained link: Wan2.1-T2V-1.3B `-Diffusers`
-- bundles the multi-GB umt5-xxl text encoder, and the routed
-- HF -> MinIO -> engine path exceeded the previous 900 s ceiling on the CUDA
-- Linux cohort host. The integration `waitForPublishedResult` deadline is sized
-- above this so a genuine bootstrap timeout still surfaces as a failed-status
-- result rather than a client-side wait expiry.
modelBootstrapReadyWaitMaxSeconds :: Int
modelBootstrapReadyWaitMaxSeconds = 3600

modelBootstrapReadyWaitAttempts :: Int
modelBootstrapReadyWaitAttempts =
  modelBootstrapReadyWaitMaxSeconds * (1000000 `div` modelBootstrapReadyPollMicros)

waitForModelBootstrapReady :: PulsarTransport -> Text.Text -> IO Bool
waitForModelBootstrapReady transport modelIdValue = do
  topicRef <- requireTopicRef readyTopic
  let readerName = "infernix-read-" <> sanitizeTopic readyTopic <> "-ready"
      readerPath = buildReaderSocketPath (pulsarWebSocketBase transport) topicRef readerName
  runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
    go connection modelBootstrapReadyWaitAttempts
  where
    readyTopic =
      BootstrapModels.bootstrapReadyTopicFor
        (qualifiedReadyTopicPrefix ConversationTopic.systemTopicNamespace)
        modelIdValue
    go connection remainingAttempts
      | remainingAttempts <= 0 = pure False
      | otherwise = do
          maybeRawEnvelope <- timeout modelBootstrapReadyPollMicros (receiveJsonFrame "Pulsar model-bootstrap ready reader message" connection)
          case maybeRawEnvelope of
            Nothing -> go connection (remainingAttempts - 1)
            Just rawEnvelope -> do
              envelope <- decodeJsonText "Pulsar model-bootstrap ready reader message" rawEnvelope
              sendAck connection (envelopeMessageId envelope)
              payloadBytes <- decodeEnvelopeBase64Payload "model-bootstrap ready" envelope
              if matchesReadyEvent payloadBytes
                then pure True
                else go connection (remainingAttempts - 1)
    matchesReadyEvent payloadBytes =
      case eitherDecodeStrict' payloadBytes of
        Right readyEvent ->
          BootstrapModels.readyEventModelId readyEvent == modelIdValue
        Left _ -> False

modelCacheBootstrapRetryableError :: ErrorResponse -> Bool
modelCacheBootstrapRetryableError errorValue =
  errorCode errorValue == "model_cache_not_populated"
    || ( errorCode errorValue == "worker_failed"
           && "model_cache_not_populated" `Text.isInfixOf` messageText
       )
    || ( errorCode errorValue == "adapter_failed"
           && any (`Text.isInfixOf` messageText) retryableMessageFragments
       )
  where
    messageText = Text.toLower (message errorValue)
    retryableMessageFragments =
      [ "modelcachenotpopulated",
        "missing the .ready sentinel",
        "published the .ready sentinel",
        "model cache config"
      ]

kvCacheRequestFromProto :: ProtoInference.InferenceRequest -> Maybe KVCache.KVCacheRequest
kvCacheRequestFromProto protoRequest = do
  let modelIdValue = view ProtoInferenceFields.requestModelId protoRequest
      contextIdValue = view ProtoInferenceFields.contextId protoRequest
      prefixHashValue = view ProtoInferenceFields.prefixHash protoRequest
  if Text.null modelIdValue || Text.null contextIdValue || Text.null prefixHashValue
    then Nothing
    else
      Just
        KVCache.KVCacheRequest
          { KVCache.kvCacheRequestContextId = contextIdValue,
            KVCache.kvCacheRequestModelId = modelIdValue,
            KVCache.kvCacheRequestPrefixHash = PrefixHash prefixHashValue
          }

decodeEnvelopePayload :: (Message a) => String -> PulsarEnvelope -> IO a
decodeEnvelopePayload payloadLabel envelope = do
  encodedPayload <-
    either
      ( \err ->
          ioError
            ( userError
                ( "failed to decode base64 "
                    <> payloadLabel
                    <> " payload for message "
                    <> Text.unpack (envelopeMessageId envelope)
                    <> ":\n"
                    <> err
                )
            )
      )
      pure
      (Base64.decode (TextEncoding.encodeUtf8 (envelopePayload envelope)))
  case decodeMessage encodedPayload of
    Left err ->
      ioError
        ( userError
            ( "failed to decode protobuf "
                <> payloadLabel
                <> " payload for message "
                <> Text.unpack (envelopeMessageId envelope)
                <> ":\n"
                <> err
            )
        )
    Right decodedValue -> pure decodedValue

sendAck :: WebSockets.Connection -> Text.Text -> IO ()
sendAck connection messageIdValue =
  sendJsonFrame connection (object ["messageId" .= messageIdValue])

sendNegativeAck :: WebSockets.Connection -> Text.Text -> IO ()
sendNegativeAck connection messageIdValue =
  sendJsonFrame
    connection
    ( object
        [ "type" .= ("negativeAcknowledge" :: String),
          "messageId" .= messageIdValue
        ]
    )

sendJsonFrame :: WebSockets.Connection -> Value -> IO ()
sendJsonFrame connection value =
  WebSockets.sendTextData connection (TextEncoding.decodeUtf8 (Lazy.toStrict (encode value)))

receiveJsonFrame :: String -> WebSockets.Connection -> IO Text.Text
receiveJsonFrame _label = WebSockets.receiveData

currentProcessLabel :: IO Text.Text
currentProcessLabel = do
  nonce <- getRandomBytes 8
  processId <- getProcessID
  pure (TextEncoding.decodeUtf8 (Base16.encode nonce) <> "-" <> Text.pack (show processId))

decodeJsonText :: (FromJSON a) => String -> Text.Text -> IO a
decodeJsonText label rawValue =
  case eitherDecodeStrict' (TextEncoding.encodeUtf8 rawValue) of
    Left err -> ioError (userError ("failed to decode " <> label <> ":\n" <> err))
    Right decodedValue -> pure decodedValue

runPulsarWebSocketClient :: PulsarWebSocketBase -> String -> (WebSockets.Connection -> IO a) -> IO a
runPulsarWebSocketClient websocketBase socketPath action =
  go (1 :: Int)
  where
    go attempt = do
      result <-
        try @SomeException $
          WebSockets.runClient (pulsarWsHost websocketBase) (pulsarWsPort websocketBase) socketPath $ \connection ->
            WebSockets.withPingThread connection 15 (pure ()) (action connection)
      case result of
        Right value -> pure value
        Left err
          | attempt < pulsarWebSocketConnectRetryAttempts,
            isRetryablePulsarWebSocketClientFailure err -> do
              threadDelay pulsarWebSocketConnectRetryDelayMicros
              go (attempt + 1)
          | otherwise -> throwIO err

pulsarWebSocketConnectRetryAttempts :: Int
pulsarWebSocketConnectRetryAttempts = 300

pulsarWebSocketConnectRetryDelayMicros :: Int
pulsarWebSocketConnectRetryDelayMicros = 1_000_000

isRetryablePulsarWebSocketClientFailure :: SomeException -> Bool
isRetryablePulsarWebSocketClientFailure err =
  not (isAsyncException err)
    && ( isConnectionRefused
           || isEarlyConnectionClosed
           || isMissingHandshakeResponse
           || isHandshakeConnectionTimeout
           || isTransientHandshakeServerError
       )
  where
    errorText = Text.toLower (Text.pack (displayException err))
    isConnectionRefused =
      "connection refused" `Text.isInfixOf` errorText
        && ( "network.socket.connect" `Text.isInfixOf` errorText
               || "failed to connect" `Text.isInfixOf` errorText
           )
    isEarlyConnectionClosed =
      case fromException err of
        Just WebSockets.ConnectionClosed -> True
        _ -> False
    isMissingHandshakeResponse =
      case fromException err of
        Just (WebSockets.OtherHandshakeException reason) ->
          "no handshake response from server" `Text.isInfixOf` Text.toLower (Text.pack reason)
        _ -> False
    isHandshakeConnectionTimeout =
      case fromException err of
        Just WebSockets.ConnectionTimeout -> True
        _ -> False
    isTransientHandshakeServerError =
      "malformedresponse" `Text.isInfixOf` errorText
        && any
          (`Text.isInfixOf` errorText)
          [ "responsecode = 500",
            "responsecode = 502",
            "responsecode = 503",
            "responsecode = 504"
          ]

-- | Build the Pulsar WebSocket producer URL with stable @producerName@
-- plus optional @initialSequenceId@ query parameters so the broker-side
-- dedup gate can track @(producerName, sequenceId)@ tuples.
buildProducerSocketPath :: PulsarWebSocketBase -> TopicRef -> Text.Text -> Maybe Integer -> String
buildProducerSocketPath websocketBase topicRef producerName maybeSequenceId =
  buildSocketPath
    websocketBase
    ("producer/" <> renderTopicPath topicRef)
    ( [("producerName", Text.unpack producerName)]
        <> maybe
          []
          (\seqId -> [("initialSequenceId", show (seqId - 1))])
          maybeSequenceId
    )

buildServiceConsumerSocketPath :: PulsarWebSocketBase -> TopicRef -> String -> String -> ConsumerSubscriptionType -> String
buildServiceConsumerSocketPath websocketBase topicRef subscriptionName consumerName subscriptionType =
  buildSocketPath
    websocketBase
    ("consumer/" <> renderTopicPath topicRef <> "/" <> subscriptionName)
    -- Service consumers choose subscription ownership from typed daemon
    -- metadata. Shared is the normal coordinator/engine-pool mode; Exclusive
    -- is reserved for pinned engine member routes. Failover is handled by
    -- coordinator-owned leadership loops, not service work fanout.
    [ ("subscriptionType", pulsarConsumerSubscriptionTypeQueryValue subscriptionType),
      ("subscriptionInitialPosition", "Earliest"),
      ("receiverQueueSize", "1"),
      ("ackTimeoutMillis", show serviceConsumerAckTimeoutMillis),
      ("consumerName", consumerName)
    ]

pulsarConsumerSubscriptionTypeQueryValue :: ConsumerSubscriptionType -> String
pulsarConsumerSubscriptionTypeQueryValue subscriptionType =
  case subscriptionType of
    ConsumerShared -> "Shared"
    ConsumerExclusive -> "Exclusive"
    ConsumerFailover -> "Failover"

buildReaderSocketPath :: PulsarWebSocketBase -> TopicRef -> String -> String
buildReaderSocketPath websocketBase topicRef readerName =
  buildSocketPath
    websocketBase
    ("reader/" <> renderTopicPath topicRef)
    [ ("messageId", "earliest"),
      ("receiverQueueSize", "1"),
      ("readerName", readerName)
    ]

buildSocketPath :: PulsarWebSocketBase -> String -> [(String, String)] -> String
buildSocketPath websocketBase relativePath =
  appendQueryParameters
    (joinSocketPath (pulsarWsPathPrefix websocketBase) relativePath)

renderTopicPath :: TopicRef -> String
renderTopicPath topicRef =
  Text.unpack (topicDomain topicRef)
    <> "/"
    <> Text.unpack (topicTenant topicRef)
    <> "/"
    <> Text.unpack (topicNamespace topicRef)
    <> "/"
    <> Text.unpack (topicName topicRef)

schemaUrl :: String -> TopicRef -> String
schemaUrl adminBaseUrl topicRef =
  trimTrailingSlash adminBaseUrl
    <> "/schemas/"
    <> Text.unpack (topicTenant topicRef)
    <> "/"
    <> Text.unpack (topicNamespace topicRef)
    <> "/"
    <> Text.unpack (topicName topicRef)
    <> "/schema"

requireTopicRef :: Text.Text -> IO TopicRef
requireTopicRef topicValue =
  case parseTopicRef topicValue of
    Just topicRef -> pure topicRef
    Nothing ->
      ioError
        (userError ("unsupported Pulsar topic name: " <> Text.unpack topicValue))

parseTopicRef :: Text.Text -> Maybe TopicRef
parseTopicRef topicValue = do
  (domainValue, remainder) <- splitOnce "://" topicValue
  case Text.splitOn "/" remainder of
    tenantValue : namespaceValue : topicSegments
      | not (Text.null tenantValue)
          && not (Text.null namespaceValue)
          && not (null topicSegments) ->
          Just
            TopicRef
              { topicDomain = domainValue,
                topicTenant = tenantValue,
                topicNamespace = namespaceValue,
                topicName = Text.intercalate "/" topicSegments
              }
    _ -> Nothing

splitOnce :: Text.Text -> Text.Text -> Maybe (Text.Text, Text.Text)
splitOnce needle haystack =
  let (prefix, suffix) = Text.breakOn needle haystack
   in if Text.null suffix
        then Nothing
        else Just (prefix, Text.drop (Text.length needle) suffix)

parsePulsarWebSocketBase :: String -> Either String PulsarWebSocketBase
parsePulsarWebSocketBase rawValue =
  case trimWhitespace rawValue of
    Nothing -> Left "the value is blank"
    Just trimmedValue -> parseTrimmedPulsarWebSocketBase trimmedValue
  where
    parseTrimmedPulsarWebSocketBase trimmedValue
      | Just valueWithoutScheme <- stripPrefix "ws://" trimmedValue =
          parseAuthorityAndPath valueWithoutScheme
      | Just _ <- stripPrefix "wss://" trimmedValue =
          Left "wss:// URLs are not supported by the current runtime; use the ws:// Pulsar proxy endpoint"
      | otherwise =
          Left "expected a ws:// URL"

    parseAuthorityAndPath valueWithoutScheme =
      case authorityAndPort authorityValue of
        Left err -> Left err
        Right (hostValue, portValue) ->
          Right
            PulsarWebSocketBase
              { pulsarWsHost = hostValue,
                pulsarWsPort = portValue,
                pulsarWsPathPrefix = pathPrefixValue
              }
      where
        (authorityValue, rawPathPrefix) = break (== '/') valueWithoutScheme
        pathPrefixValue = trimTrailingSlash rawPathPrefix

authorityAndPort :: String -> Either String (String, Int)
authorityAndPort rawAuthority =
  case break (== ':') rawAuthority of
    ("", _) -> Left "missing host"
    (hostValue, "") -> Right (hostValue, 80)
    (hostValue, ':' : rawPort)
      | null rawPort -> Left "missing port"
      | otherwise ->
          case reads rawPort of
            [(portValue, "")] -> Right (hostValue, portValue)
            _ -> Left ("invalid port: " <> rawPort)
    _ -> Left "invalid authority"

renderPulsarWebSocketBase :: PulsarWebSocketBase -> String
renderPulsarWebSocketBase websocketBase =
  "ws://"
    <> pulsarWsHost websocketBase
    <> ":"
    <> show (pulsarWsPort websocketBase)
    <> if null (pulsarWsPathPrefix websocketBase)
      then ""
      else pulsarWsPathPrefix websocketBase

joinSocketPath :: String -> String -> String
joinSocketPath basePath relativePath =
  case normalizedBasePath basePath of
    "" -> '/' : normalizedRelative
    normalizedBase -> normalizedBase <> "/" <> normalizedRelative
  where
    normalizedRelative = dropWhile (== '/') relativePath

normalizedBasePath :: String -> String
normalizedBasePath basePath =
  case trimTrailingSlash basePath of
    "" -> ""
    value -> ensureLeadingSlash value

ensureLeadingSlash :: String -> String
ensureLeadingSlash value =
  case value of
    '/' : _ -> value
    _ -> '/' : value

appendQueryParameters :: String -> [(String, String)] -> String
appendQueryParameters basePath [] = basePath
appendQueryParameters basePath queryParameters =
  basePath <> "?" <> intercalate "&" (map (\(key, value) -> key <> "=" <> value) queryParameters)

sanitizeTopic :: Text.Text -> FilePath
sanitizeTopic =
  map replaceSeparator . Text.unpack
  where
    replaceSeparator '/' = '_'
    replaceSeparator ':' = '_'
    replaceSeparator '.' = '_'
    replaceSeparator character = character

protoRequestToDomain :: ProtoInference.InferenceRequest -> InferenceRequest
protoRequestToDomain protoRequest =
  InferenceRequest
    { requestModelId = view ProtoInferenceFields.requestModelId protoRequest,
      inputText = view ProtoInferenceFields.inputText protoRequest,
      -- Phase 4 Sprint 4.15: an empty wire field means the text families'
      -- "no input object reference"; non-text input families carry the ref.
      inputObjectRef = nonEmptyText (view ProtoInferenceFields.inputObjectRef protoRequest),
      requestUserId = nonEmptyText (view ProtoInferenceFields.userId protoRequest),
      requestContextId = nonEmptyText (view ProtoInferenceFields.contextId protoRequest)
    }

nonEmptyText :: Text.Text -> Maybe Text.Text
nonEmptyText value
  | Text.null value = Nothing
  | otherwise = Just value

rawTopicInferenceRequestPromptIds :: [RawTopicMessage] -> [Text.Text]
rawTopicInferenceRequestPromptIds messages =
  [ view (field @"userPromptMessageId") request
  | rawMessage <- messages,
    Right request <- [decodeMessage (rawTopicMessagePayload rawMessage) :: Either String ProtoInference.InferenceRequest]
  ]

rawTopicInferenceRequestIds :: [RawTopicMessage] -> [Text.Text]
rawTopicInferenceRequestIds messages =
  [ view (field @"requestId") request
  | rawMessage <- messages,
    Right request <- [decodeMessage (rawTopicMessagePayload rawMessage) :: Either String ProtoInference.InferenceRequest]
  ]

rawTopicInferenceResultCausalRefs :: [RawTopicMessage] -> [Text.Text]
rawTopicInferenceResultCausalRefs messages =
  [ view (field @"causalRef") resultValue
  | rawMessage <- messages,
    Right resultValue <- [decodeMessage (rawTopicMessagePayload rawMessage) :: Either String ProtoInference.InferenceResult]
  ]

domainResultToProto :: InferenceResult -> ProtoInference.InferenceResult
domainResultToProto resultValue =
  set (field @"requestId") (requestId resultValue) $
    set (field @"resultModelId") (resultModelId resultValue) $
      set (field @"matrixRowId") (resultMatrixRowId resultValue) $
        set (field @"runtimeMode") (runtimeModeId (resultRuntimeMode resultValue)) $
          set (field @"selectedEngine") (resultSelectedEngine resultValue) $
            set (field @"status") (status resultValue) $
              set (field @"payload") (resultPayloadToProto (payload resultValue)) $
                set (field @"createdAt") (formatTimestamp (createdAt resultValue)) $
                  set (field @"userId") (resultUserId resultValue) $
                    set (field @"contextId") (resultContextId resultValue) $
                      set (field @"causalRef") (resultCausalRef resultValue) defMessage

protoResultToDomain :: ProtoInference.InferenceResult -> Maybe InferenceResult
protoResultToDomain protoResult = do
  parsedRuntimeMode <- parseRuntimeMode (view ProtoInferenceFields.runtimeMode protoResult)
  parsedPayload <- protoPayloadToDomain (view ProtoInferenceFields.payload protoResult)
  parsedCreatedAt <- parseTimestamp (view ProtoInferenceFields.createdAt protoResult)
  pure
    InferenceResult
      { requestId = view ProtoInferenceFields.requestId protoResult,
        resultModelId = view ProtoInferenceFields.resultModelId protoResult,
        resultMatrixRowId = view ProtoInferenceFields.matrixRowId protoResult,
        resultRuntimeMode = parsedRuntimeMode,
        resultSelectedEngine = view ProtoInferenceFields.selectedEngine protoResult,
        status = view ProtoInferenceFields.status protoResult,
        payload = parsedPayload,
        createdAt = parsedCreatedAt,
        resultUserId = view ProtoInferenceFields.userId protoResult,
        resultContextId = view ProtoInferenceFields.contextId protoResult,
        resultCausalRef = view ProtoInferenceFields.causalRef protoResult
      }

resultPayloadToProto :: ResultPayload -> ProtoInference.ResultPayload
resultPayloadToProto payloadValue =
  case objectRef payloadValue of
    Just objectRefValue -> set (field @"objectRef") objectRefValue defMessage
    Nothing -> set (field @"inlineOutput") (fromMaybe "" (inlineOutput payloadValue)) defMessage

protoPayloadToDomain :: ProtoInference.ResultPayload -> Maybe ResultPayload
protoPayloadToDomain protoPayload =
  case view ProtoInferenceFields.maybe'output protoPayload of
    Just (ProtoInference.ResultPayload'InlineOutput inlineOutputValue) ->
      Just (ResultPayload {inlineOutput = Just inlineOutputValue, objectRef = Nothing})
    Just (ProtoInference.ResultPayload'ObjectRef objectRefValue) ->
      Just (ResultPayload {inlineOutput = Nothing, objectRef = Just objectRefValue})
    Nothing ->
      Just (ResultPayload {inlineOutput = Just "", objectRef = Nothing})

writeInferenceRequestFile :: FilePath -> ProtoInference.InferenceRequest -> IO ()
writeInferenceRequestFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  writeFileBytes filePath (encodeMessage value)

writeInferenceResultFile :: FilePath -> ProtoInference.InferenceResult -> IO ()
writeInferenceResultFile filePath value = do
  createDirectoryIfMissing True (takeDirectory filePath)
  writeFileBytes filePath (encodeMessage value)

readFileBytes :: FilePath -> IO ByteString.ByteString
readFileBytes = ByteString.readFile

writeFileBytes :: FilePath -> ByteString.ByteString -> IO ()
writeFileBytes = ByteString.writeFile

endsWith :: String -> String -> Bool
endsWith suffix value = reverse suffix `startsWith` reverse value

startsWith :: String -> String -> Bool
startsWith [] _ = True
startsWith _ [] = False
startsWith (expected : expectedRest) (actual : actualRest) =
  expected == actual && startsWith expectedRest actualRest

trimWhitespace :: String -> Maybe String
trimWhitespace rawValue =
  let trimmed = dropWhileEnd (`elem` [' ', '\n', '\r', '\t']) (dropWhile (`elem` [' ', '\n', '\r', '\t']) rawValue)
   in if null trimmed then Nothing else Just trimmed

generatePublishedRequestId :: IO Text.Text
generatePublishedRequestId =
  Text.pack . formatTime defaultTimeLocale "req-%Y%m%d%H%M%S%q" <$> getCurrentTime

trimTrailingSlash :: String -> String
trimTrailingSlash = reverse . dropWhile (== '/') . reverse

dropWhileEnd :: (Char -> Bool) -> String -> String
dropWhileEnd predicate = reverse . dropWhile predicate . reverse

stripPrefix :: String -> String -> Maybe String
stripPrefix [] value = Just value
stripPrefix _ [] = Nothing
stripPrefix (expected : expectedRest) (actual : actualRest)
  | expected == actual = stripPrefix expectedRest actualRest
  | otherwise = Nothing

lazyBodyToString :: Lazy.ByteString -> String
lazyBodyToString = ByteString8.unpack . Lazy.toStrict
