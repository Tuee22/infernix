{-# LANGUAGE DataKinds #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Runtime.Pulsar
  ( DemoClientMessagePublication (..),
    DemoClientMessageError (..),
    RawTopicMessage (..),
    compactTopicAndWait,
    planDemoClientMessagePublications,
    publishDemoClientMessage,
    streamDemoContextConversation,
    streamDemoUserMetadata,
    publishRawTopicPayload,
    validateDemoClientMessageCatalog,
    publishInferenceRequest,
    readNamespaceCompactionThreshold,
    readRawTopicPayloads,
    readPublishedInferenceResultMaybe,
    drainTopic,
    runDispatcherLoop,
    runModelBootstrapLoop,
    runProductionDaemon,
    runResultBridgeLoop,
    schemaMarkerPath,
    serviceReadinessMarkerPath,
    topicDirectoryPath,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (forkIO, threadDelay)
import Control.Concurrent.MVar (MVar, modifyMVar_, newMVar)
import Control.Exception (Exception, SomeAsyncException, SomeException, displayException, fromException, throwIO, try)
import Control.Monad (forM_, forever, unless, void, when)
import Crypto.Hash.SHA256 qualified as SHA256
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
import Data.ByteString qualified as ByteString
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as Lazy
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.List (intercalate, sort)
import Data.Map.Strict (Map)
import Data.Map.Strict qualified as Map
import Data.Maybe (fromMaybe)
import Data.ProtoLens (Message, decodeMessage, defMessage, encodeMessage)
import Data.ProtoLens.Field (field)
import Data.Set (Set)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time (UTCTime, defaultTimeLocale, formatTime, getCurrentTime, parseTimeM)
import Infernix.Bootstrap.Models qualified as BootstrapModels
import Infernix.Bridge.Result qualified as ResultBridge
import Infernix.ClusterConfig
  ( ClusterConfig (..),
    CoordinatorWiring (..),
    DemoBackendWiring (..),
    EngineCommandOverride (..),
    EngineWiring (..),
    PulsarWiring (..),
  )
import Infernix.ClusterConfig qualified as Cluster
import Infernix.Config
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
import Infernix.Objects.Presigned qualified as Presigned
import Infernix.Runtime (executeInference)
import Infernix.Runtime.Worker (EngineCommandOverrideMap)
import Infernix.SecretsConfig qualified as Secrets
import Infernix.Storage (readEdgePortMaybe)
import Infernix.Types
import Infernix.Web.Contracts qualified as Contracts
import Lens.Family2 (set, view)
import Network.HTTP.Client
  ( Manager,
    RequestBody (RequestBodyLBS),
    defaultManagerSettings,
    httpLbs,
    method,
    newManager,
    parseRequest,
    requestBody,
    requestHeaders,
    responseBody,
    responseStatus,
  )
import Network.HTTP.Types.Status (statusCode)
import Network.WebSockets qualified as WebSockets
import Proto.Infernix.Runtime.Inference qualified as ProtoInference
import Proto.Infernix.Runtime.Inference_Fields qualified as ProtoInferenceFields
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
    removeFile,
  )
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath (takeDirectory, (<.>), (</>))
import System.IO (hPutStrLn, stderr)
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

data LongRunningProcessStatus = LongRunningProcessStatus
  { longRunningProcessStatus :: Text.Text,
    longRunningProcessLastError :: Maybe Text.Text
  }
  deriving (Eq, Show)

data HostDiscoveredPublication = HostDiscoveredPublication
  { hostPublicationClusterPresent :: Bool,
    hostPublicationEdgePort :: Maybe Int
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
      <*> value .:? "edgePort"

instance FromJSON LongRunningProcessStatus where
  parseJSON = withObject "LongRunningProcessStatus" $ \value ->
    LongRunningProcessStatus
      <$> value .: "status"
      <*> value .:? "lastError"

-- | Phase 4 Sprint 4.13: env-var override family retired. Wiring
-- values previously read from @INFERNIX_CONTROL_PLANE_CONTEXT@,
-- @INFERNIX_DAEMON_ROLE@, @INFERNIX_DAEMON_LOCATION@,
-- @INFERNIX_CATALOG_SOURCE@, @INFERNIX_DEMO_CONFIG_PATH@ now flow
-- through typed arguments: the 'ClusterConfig' (optional, mounted by
-- the chart into cluster pods at @/opt/infernix/cluster.dhall@)
-- supplies cluster-wiring overrides; the 'DaemonRole' supplied by the
-- caller (typically 'Infernix.Service.runService' after parsing the
-- @--role coordinator|engine@ CLI flag) replaces the role env var;
-- everything else falls back to the substrate dhall + 'Paths'
-- defaults.
runProductionDaemon :: Paths -> RuntimeMode -> Maybe ClusterConfig -> DaemonRole -> IO ()
runProductionDaemon paths runtimeMode maybeClusterConfig daemonRole = do
  maybeTransport <- discoverPulsarTransport paths runtimeMode maybeClusterConfig
  let controlPlane = case maybeClusterConfig of
        Just clusterConfig -> resolveClusterControlPlaneContext clusterConfig (controlPlaneContext paths)
        Nothing -> controlPlaneContext paths
      catalogSource = case maybeClusterConfig of
        Just clusterConfig -> Text.unpack (coordinatorCatalogSource (clusterCoordinator clusterConfig))
        Nothing -> demoConfigCatalogSource
      selectedDemoConfigPath = case maybeClusterConfig of
        Just clusterConfig ->
          let demoPath = Text.unpack (demoConfigFilePath (clusterDemoBackend clusterConfig))
           in if null demoPath then Infernix.Config.generatedDemoConfigPath paths else demoPath
        Nothing -> Infernix.Config.generatedDemoConfigPath paths
      -- Phase 4 Sprint 4.13: engine-command overrides are read once from
      -- the mounted cluster manifest's @engine.commandOverrides@ field
      -- and threaded through to the worker. Empty list when no manifest
      -- is mounted (Apple host daemon, unit tests).
      engineOverrides = case maybeClusterConfig of
        Just clusterConfig ->
          map
            (\override -> (engineOverrideKey override, engineOverrideValue override))
            (engineCommandOverrides (clusterEngine clusterConfig))
        Nothing -> []
  demoConfig <- decodeDemoConfigFile selectedDemoConfigPath
  daemonConfig <- requireDaemonConfig daemonRole demoConfig
  let daemonLocation = case maybeClusterConfig of
        Just clusterConfig ->
          let mounted = Text.unpack (coordinatorDaemonLocation (clusterCoordinator clusterConfig))
           in if null mounted then Text.unpack (daemonConfigLocation daemonConfig) else mounted
        Nothing -> Text.unpack (daemonConfigLocation daemonConfig)
  putStrLn ("serviceControlPlaneContext: " <> controlPlaneContextId controlPlane)
  putStrLn ("serviceDaemonRole: " <> Text.unpack (daemonRoleId daemonRole))
  putStrLn ("serviceDaemonLocation: " <> daemonLocation)
  putStrLn ("serviceCatalogSource: " <> catalogSource)
  putStrLn ("serviceRuntimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("serviceDemoConfigPath: " <> selectedDemoConfigPath)
  putStrLn ("serviceMountedDemoConfigPath: " <> watchedDemoConfigPath)
  putStrLn ("serviceRequestTopics: " <> intercalate "," (map Text.unpack (daemonConfigRequestTopics daemonConfig)))
  putStrLn ("serviceResultTopic: " <> Text.unpack (daemonConfigResultTopic daemonConfig))
  forM_ (daemonConfigHostBatchTopic daemonConfig) $ \topicValue ->
    putStrLn ("serviceHostBatchTopic: " <> Text.unpack topicValue)
  putStrLn ("serviceEngineBindingCount: " <> show (length (engines demoConfig)))
  putStrLn "serviceHttpListener: disabled"
  clearServiceReadinessMarker paths
  case maybeTransport of
    Nothing -> do
      ensureSchemaMarkers paths demoConfig
      writeServiceReadinessMarker paths
      putStrLn "serviceSubscriptionMode: filesystem-topic-spool"
      forever $ do
        forM_ (daemonConfigRequestTopics daemonConfig) (drainTopic paths runtimeMode engineOverrides daemonConfig)
        threadDelay 500000
    Just transport -> do
      ensureSchemaMarkers paths demoConfig
      reconcileSupportedNamespacesWithRetry transport demoConfig
      ensureRegisteredSchemasWithRetry paths transport demoConfig
      writeServiceReadinessMarker paths
      putStrLn "serviceSubscriptionMode: websocket-pulsar"
      putStrLn ("servicePulsarWsBaseUrl: " <> renderPulsarWebSocketBase (pulsarWebSocketBase transport))
      forM_
        (daemonConfigRequestTopics daemonConfig)
        (forkIO . consumeTopicForever transport paths runtimeMode engineOverrides daemonConfig)
      -- Phase 7 Sprint 7.8: when running as Coordinator, also start the
      -- result-bridge Failover subscription. The bridge consumes
      -- @inference.result.<mode>@ and writes the matching
      -- @ConversationInferenceResultEvent@ back to the per-context
      -- conversation topic. The Engine role does not start this loop;
      -- it produces results to @inference.result.<mode>@ and the
      -- bridge owns the writeback.
      when (daemonRole == Coordinator) $ do
        putStrLn "serviceResultBridgeMode: failover-subscription"
        _ <-
          forkIO
            ( runResultBridgeLoop
                transport
                runtimeMode
                (daemonConfigResultTopic daemonConfig)
                ConversationTopic.defaultDemoTopicNamespace
            )
        putStrLn "serviceModelBootstrapMode: failover-subscription"
        _ <-
          forkIO
            ( runModelBootstrapLoop
                transport
                ConversationTopic.systemTopicNamespace
            )
        -- Phase 7 Sprint 7.6: per-context single-flight dispatcher loop.
        -- Polls @infernix/demo@ for @demo.conversation.<userId>.<contextId>@
        -- topics, spawns a per-context worker keyed by 'ContextId' that
        -- subscribes Failover (name @dispatcher-<contextId>@), folds events
        -- through 'Infernix.Conversation.Reducer', and publishes
        -- 'Infernix.Dispatch.SingleFlight.InferenceRequestEnvelope' to the
        -- substrate's request topic with stable producer name and
        -- 'producerDedupSequenceId'. Engine role does not start this loop.
        putStrLn "serviceDispatcherMode: per-context-failover"
        contextModelMap <- ContextModelMap.newContextModelMap
        _ <-
          forkIO
            ( runDispatcherLoop
                transport
                runtimeMode
                (firstOrEmpty (daemonConfigRequestTopics daemonConfig))
                ConversationTopic.defaultDemoTopicNamespace
                contextModelMap
            )
        pure ()
      forever (threadDelay 60000000)
  where
    firstOrEmpty :: [Text.Text] -> Text.Text
    firstOrEmpty [] = ""
    firstOrEmpty (topic : _) = topic

-- | Phase 4 Sprint 4.13: resolve the control-plane context from a
-- mounted cluster manifest when available, falling back to the
-- 'Paths'-derived value (the supported host-native default).
resolveClusterControlPlaneContext :: ClusterConfig -> ControlPlaneContext -> ControlPlaneContext
resolveClusterControlPlaneContext clusterConfig fallback =
  let mounted = Text.unpack (coordinatorControlPlaneContext (clusterCoordinator clusterConfig))
   in fromMaybe fallback (parseControlPlaneContext mounted)

-- | Phase 4 Sprint 4.13: the previous helper accepted a
-- @Maybe FilePath@ encoding the now-retired @INFERNIX_DEMO_CONFIG_PATH@
-- env override. The supported flow now always falls through to the
-- staged substrate dhall, so the source identifier is constant. The
-- 'ClusterConfig.coordinator.catalogSource' field provides the
-- in-cluster override.
demoConfigCatalogSource :: String
demoConfigCatalogSource = "generated-build-root"

requireDaemonConfig :: DaemonRole -> DemoConfig -> IO DaemonConfig
requireDaemonConfig daemonRole demoConfig
  | daemonConfigRole (coordinatorDaemon demoConfig) == daemonRole =
      pure (coordinatorDaemon demoConfig)
  | otherwise =
      case engineDaemon demoConfig of
        Just daemonConfig
          | daemonConfigRole daemonConfig == daemonRole ->
              pure daemonConfig
        _ ->
          ioError
            ( userError
                ( "generated substrate file does not contain daemon metadata for role "
                    <> Text.unpack (daemonRoleId daemonRole)
                )
            )

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
              set (field @"runtimeMode") (runtimeModeId runtimeMode) defMessage
  case maybeTransport of
    Nothing -> do
      createDirectoryIfMissing True (topicDirectoryPath paths topic)
      let outputPath = topicDirectoryPath paths topic </> Text.unpack requestIdValue <.> "pb"
      writeInferenceRequestFile outputPath protoPayload
      pure requestIdValue
    Just transport -> do
      -- Phase 7 Sprint 7.7: stable producer name per
      -- @inference.request.<mode>@ topic so the broker dedup gate can
      -- track @(producerName, sequenceId)@ tuples across coordinator
      -- replicas. Application-level dedup key derivation lives in
      -- @Infernix.Dispatch.SingleFlight.producerDedupSequenceId@; the
      -- direct @infernix-demo@ producer path leaves @sequenceId@
      -- unset so retries from this code path do not collide with the
      -- coordinator's typed envelope.
      let options =
            defaultPublishOptions
              ( "infernix-demo-publisher-"
                  <> runtimeModeId runtimeMode
              )
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
  void $
    forkIO
      (streamUserContextListViaPulsar transport namespace userIdValue sendMessage)
  void $
    forkIO
      (streamUserDraftMapViaPulsar transport namespace userIdValue sendMessage)
  forever (threadDelay 60_000_000)

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
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
            forever
              (handleContextMetadataStreamMessage stateRef sendMessage connection)
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "browser context-list stream for "
              <> Text.unpack contextsTopic
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

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
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
            forever
              (handleDraftMetadataStreamMessage stateRef sendMessage connection)
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "browser draft-map stream for "
              <> Text.unpack draftsTopic
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

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
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) readerPath $ \connection ->
            forever
              ( handleConversationStreamMessage
                  contextIdValue
                  reducerStateRef
                  seenMessageIdsRef
                  sendMessage
                  connection
              )
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "browser context stream for "
              <> Text.unpack conversationTopic
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

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

drainTopic :: Paths -> RuntimeMode -> EngineCommandOverrideMap -> DaemonConfig -> Text.Text -> IO ()
drainTopic paths runtimeMode overrides daemonConfig requestTopicValue =
  case daemonConfigHostBatchTopic daemonConfig of
    Just hostBatchTopicValue ->
      forwardTopic paths hostBatchTopicValue requestTopicValue
    _ ->
      drainInferenceTopic paths runtimeMode overrides (daemonConfigResultTopic daemonConfig) requestTopicValue

forwardTopic :: Paths -> Text.Text -> Text.Text -> IO ()
forwardTopic paths targetTopicValue sourceTopicValue = do
  let sourceDirectory = topicDirectoryPath paths sourceTopicValue
  sourceDirectoryPresent <- doesDirectoryExist sourceDirectory
  unless sourceDirectoryPresent (createDirectoryIfMissing True sourceDirectory)
  requestFiles <- sort <$> listDirectory sourceDirectory
  forM_ (filter (".pb" `endsWith`) requestFiles) $ \requestFile -> do
    let sourcePath = sourceDirectory </> requestFile
        targetDirectory = topicDirectoryPath paths targetTopicValue
        targetPath = targetDirectory </> requestFile
    encodedRequest <- readFileBytes sourcePath
    createDirectoryIfMissing True targetDirectory
    ByteString.writeFile targetPath encodedRequest
    removeFile sourcePath

drainInferenceTopic :: Paths -> RuntimeMode -> EngineCommandOverrideMap -> Text.Text -> Text.Text -> IO ()
drainInferenceTopic paths runtimeMode overrides resultTopicValue requestTopicValue = do
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
        publishedResult <- publishedResultFromRequest paths runtimeMode overrides protoRequest
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
-- Pulsar transport discovery via the kind control-plane's IPv4 +
-- NodePort 30090. The launcher cannot use @127.0.0.1:9090@ from
-- inside its own network namespace, and Kind's docker-DNS entry for
-- @<cluster>-control-plane@ returns an IPv6 ULA address first
-- (@fc00:f853:ccd:e793::/64@) that Haskell's getAddrInfo+connect
-- doesn't route on the kind bridge. The supported flow asks Docker
-- for the kind control-plane container's IPv4 on the @kind@ network
-- directly, then connects to that explicit IPv4 on the supported
-- NodePort 30090 — which the launcher reaches over the attached
-- @kind@ bridge via @ensureOuterContainerKindNetworkAccess@.
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
    outerContainerPort = 30090 :: Int
    wsUrl =
      "ws://" <> ipv4 <> ":" <> show outerContainerPort <> "/pulsar/ws/v2"
    adminUrl =
      "http://" <> ipv4 <> ":" <> show outerContainerPort <> "/pulsar/admin/admin/v2"

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
              maybeEdgePort <- readEdgePortMaybe paths
              let selectedPort = maybeEdgePort <|> hostPublicationEdgePort publication
              case selectedPort of
                Nothing -> pure Nothing
                Just edgePortValue ->
                  buildLoopbackTransport edgePortValue
  where
    buildLoopbackTransport edgePortValue =
      case parsePulsarWebSocketBase ("ws://127.0.0.1:" <> show edgePortValue <> "/pulsar/ws/v2") of
        Left err ->
          ioError
            ( userError
                ( "failed to construct the Apple host-native Pulsar websocket endpoint from the published edge port:\n"
                    <> err
                )
            )
        Right websocketBase ->
          pure
            ( Just
                PulsarTransport
                  { pulsarAdminBaseUrl = Just ("http://127.0.0.1:" <> show edgePortValue <> "/pulsar/admin/admin/v2"),
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
  ensureRemoteSchema manager adminBaseUrl (resultTopic demoConfig) "infernix.runtime.InferenceResult"

schemaTopicsForDemoConfig :: DemoConfig -> [Text.Text]
schemaTopicsForDemoConfig demoConfig =
  uniqueTexts (requestLikeSchemaTopics demoConfig <> [resultTopic demoConfig])

requestLikeSchemaTopics :: DemoConfig -> [Text.Text]
requestLikeSchemaTopics demoConfig =
  uniqueTexts
    ( requestTopics demoConfig
        <> daemonConfigRequestTopics (coordinatorDaemon demoConfig)
        <> maybe [] daemonConfigRequestTopics (engineDaemon demoConfig)
        <> maybe [] pure (daemonConfigHostBatchTopic (coordinatorDaemon demoConfig))
        <> maybe [] (maybe [] pure . daemonConfigHostBatchTopic) (engineDaemon demoConfig)
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
  -- The bootstrap request topic itself. Pulsar auto-creates topics on
  -- first produce when @allowAutoTopicCreation = true@; doing the
  -- create-here belt-and-braces means daemon startup logs a clear error
  -- if broker policy disables auto-creation.
  ensureNonPartitionedTopic
    manager
    adminBaseUrl
    "persistent://infernix/system/model.bootstrap.request"

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
  Text.Text ->
  IO ()
consumeTopicForever transport paths runtimeMode overrides daemonConfig requestTopicValue =
  forever $ do
    sessionResult <- try @SomeException (consumeTopicSession transport paths runtimeMode overrides daemonConfig requestTopicValue)
    case sessionResult of
      Right _ -> threadDelay 1000000
      Left err -> do
        hPutStrLn
          stderr
          ( "pulsar consumer loop failed for "
              <> Text.unpack requestTopicValue
              <> ":\n"
              <> displayException err
          )
        threadDelay 1000000

consumeTopicSession ::
  PulsarTransport ->
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  DaemonConfig ->
  Text.Text ->
  IO ()
consumeTopicSession transport paths runtimeMode overrides daemonConfig requestTopicValue = do
  topicRef <- requireTopicRef requestTopicValue
  let subscriptionName = "infernix-service-" <> sanitizeTopic requestTopicValue
      consumerName = subscriptionName <> "-consumer"
      consumerPath =
        buildConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          subscriptionName
          consumerName
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
      -- Forward to the host-batch topic whenever the active daemon config
      -- names one. Sprint 7.7 generalises this from an AppleSilicon-only
      -- conditional to "every substrate honors the configured handoff
      -- topic" so the cluster coordinator can hand off to a per-substrate
      -- engine pool uniformly. When no host-batch topic is configured the
      -- daemon executes inference inline and publishes the result itself.
      case daemonConfigHostBatchTopic daemonConfig of
        Just hostBatchTopicValue -> do
          -- Coordinator-role hand-off to the engine-batch topic. The
          -- producer name is stable per coordinator role so the broker
          -- dedups concurrent coordinator replicas. Sequence-id
          -- derivation from the application-level
          -- @userPromptMessageId@ key lives in
          -- @Infernix.Dispatch.SingleFlight.producerDedupSequenceId@;
          -- the broker-side dedup gate ('reconcileSupportedNamespaces')
          -- accepts the resulting tuple. Phase 7 Sprint 7.14 wires the
          -- typed envelope read here.
          let batchOptions =
                (defaultPublishOptions ("infernix-coordinator-batch-" <> runtimeModeId runtimeMode))
                  { publishSequenceId = inferenceRequestSequenceId decodedRequest
                  }
          publishTopicPayload
            transport
            hostBatchTopicValue
            batchOptions
            (view ProtoInferenceFields.requestId decodedRequest)
            (encodeMessage decodedRequest)
        Nothing -> do
          let modelIdValue = view ProtoInferenceFields.requestModelId decodedRequest
              requestIdValue = view ProtoInferenceFields.requestId decodedRequest
          publishedResult <-
            if Text.null modelIdValue
              then pure (emptyModelIdRejectionResult runtimeMode decodedRequest)
              else publishedResultFromRequest paths runtimeMode overrides decodedRequest
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
          let resultOptions =
                (defaultPublishOptions ("infernix-engine-result-" <> runtimeModeId runtimeMode))
                  { publishSequenceId = inferenceRequestSequenceId decodedRequest
                  }
          publishTopicPayload
            transport
            (daemonConfigResultTopic daemonConfig)
            resultOptions
            (requestId publishedResult)
            (encodeMessage (domainResultToProto publishedResult))
      sendAck connection (envelopeMessageId envelope)

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

-- | Derive a per-message Pulsar dedup @sequenceId@ from an envelope's
-- @userPromptMessageId@. Pulsar MessageIds serialize as
-- @<ledgerId>:<entryId>:<partition>:<batchIdx>@; we pack ledger and
-- entry into a 64-bit value because both are monotonic per
-- topic-partition. The supported per-context dispatcher in
-- 'Infernix.Dispatch.SingleFlight' uses one producer per context, so
-- the resulting sequence is monotonic within a producer scope. If the
-- envelope's @userPromptMessageId@ is empty or unparseable (legacy
-- inference-request envelopes that predate Sprint 7.8), the helper
-- returns 'Nothing' and the broker assigns the sequence so dedup
-- degenerates to producer-name stability without breaking the publish.
inferenceRequestSequenceId :: ProtoInference.InferenceRequest -> Maybe Integer
inferenceRequestSequenceId request =
  parseMessageIdToSequenceId (view ProtoInferenceFields.userPromptMessageId request)

parseMessageIdToSequenceId :: Text.Text -> Maybe Integer
parseMessageIdToSequenceId raw =
  case Text.splitOn ":" raw of
    (ledgerText : entryText : _) -> do
      ledger <- parseInteger ledgerText
      entry <- parseInteger entryText
      pure (ledger * (2 ^ (32 :: Int)) + entry)
    _ -> Nothing
  where
    parseInteger value =
      case reads (Text.unpack value) :: [(Integer, String)] of
        [(parsed, "")] -> Just parsed
        _ -> Nothing

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
  runPulsarWebSocketClient (pulsarWebSocketBase transport) producerPath $ \connection -> do
    sendJsonFrame connection producerPayload
    rawResponse <- receiveJsonFrame "Pulsar producer response" connection
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
  let runtimeModeText = runtimeModeId runtimeMode
      subscriptionName = "result-bridge-" <> runtimeModeText
      consumerName = subscriptionName <> "-consumer"
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
      inlineOutputValue = case payload resultValue of
        ResultPayload {inlineOutput = Just text} -> Just text
        _ -> Nothing
      objectRefValue = case payload resultValue of
        ResultPayload {objectRef = Just rawKey} ->
          -- The result envelope's @ObjectRef@ field stores a single
          -- string ("bucket/key" or just a key); the conversation
          -- event surface carries the structured ObjectRef the
          -- browser uses to mint presigned URLs. Default to the demo
          -- bucket when only a key is supplied.
          [ Contracts.ObjectRef
              { Contracts.objectBucket = "infernix-demo-objects",
                Contracts.objectKey = rawKey
              }
          ]
        _ -> []
      conversationEvent =
        ResultBridge.inferenceResultEventFor
          (Contracts.MessageId causalRef)
          (status resultValue)
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
  IO ()
runDispatcherLoop transport runtimeMode requestTopic topicNamespace contextModelMap
  | Text.null requestTopic = do
      hPutStrLn
        stderr
        "dispatcher loop disabled: daemon config has no inference request topic"
      forever (threadDelay 60_000_000)
  | otherwise = do
      managedContexts <- newMVar Set.empty
      managedUsers <- newMVar Set.empty
      manager <- newManager defaultManagerSettings
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
  IO ()
discoverAndStartDispatchers transport runtimeMode requestTopic topicNamespace manager managedContexts managedUsers contextModelMap = do
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
  IO ()
startDispatcherWorkerIfNeeded transport runtimeMode requestTopic conversationTopic userIdValue contextIdValue managedContexts contextModelMap = do
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
              )
          )
        pure (Set.insert userIdText alreadyStarted)

-- | The per-user compacted-topic consumer. Subscribes Exclusive (the
-- contexts topic is per-user so no Failover or Shared semantics are
-- needed), reads from the earliest broker offset so the compacted view
-- is replayed on cold coordinator startup, decodes each frame as a
-- 'Contracts.ContextMetadataEvent', and updates the shared map via
-- 'ContextModelMap.recordContextMetadataEvent'. Frames the SPA has not
-- written yet simply don't surface here; the supported flow surfaces a
-- typed engine error result when 'lookupModelId' returns 'Nothing' at
-- dispatch time.
runContextsMetadataConsumer ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  Contracts.UserId ->
  ContextModelMap ->
  IO ()
runContextsMetadataConsumer transport topicNamespace userIdValue contextModelMap = do
  let topicUrl = ConversationTopic.contextsMetadataTopicName topicNamespace userIdValue
      Contracts.UserId userIdText = userIdValue
      subscriptionName = "infernix-coordinator-context-model-map-" <> userIdText
      consumerName = subscriptionName <> "-consumer"
  topicRef <- requireTopicRef topicUrl
  let consumerPath =
        buildFailoverConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          (Text.unpack subscriptionName)
          (Text.unpack consumerName)
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
            forever (handleContextsMetadataMessage contextModelMap connection)
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "contexts metadata session for "
              <> Text.unpack topicUrl
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

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
  IO ()
runDispatcherForContext transport runtimeMode requestTopic conversationTopic userIdValue contextIdValue contextModelMap = do
  reducerStateRef <- newIORef (initialReducerState contextIdValue)
  let subscriptionName = Dispatch.dispatcherSubscriptionName contextIdValue
      consumerName = subscriptionName <> "-consumer"
  topicRef <- requireTopicRef conversationTopic
  let consumerPath =
        buildFailoverConsumerSocketPath
          (pulsarWebSocketBase transport)
          topicRef
          (Text.unpack subscriptionName)
          (Text.unpack consumerName)
  forever $ do
    sessionResult <-
      try @SomeException
        ( runPulsarWebSocketClient (pulsarWebSocketBase transport) consumerPath $ \connection ->
            forever
              ( handleDispatcherMessage
                  transport
                  runtimeMode
                  requestTopic
                  userIdValue
                  contextIdValue
                  reducerStateRef
                  contextModelMap
                  connection
              )
        )
    case sessionResult of
      Right _ -> threadDelay 1_000_000
      Left err -> do
        hPutStrLn
          stderr
          ( "dispatcher session for "
              <> Text.unpack conversationTopic
              <> " failed:\n"
              <> displayException err
          )
        threadDelay 1_000_000

handleDispatcherMessage ::
  PulsarTransport ->
  RuntimeMode ->
  Text.Text ->
  Contracts.UserId ->
  Contracts.ContextId ->
  IORef ReducerState ->
  ContextModelMap ->
  WebSockets.Connection ->
  IO ()
handleDispatcherMessage transport runtimeMode requestTopic userIdValue contextIdValue reducerStateRef contextModelMap connection = do
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
              decision <- atomicModifyIORef' reducerStateRef $ \state ->
                case stepReducer state conversationMessage of
                  StepAdvanced advancedState _ ->
                    (advancedState, Dispatch.buildDispatchDecision userIdValue advancedState)
                  StepDropped unchanged ->
                    (unchanged, Dispatch.DispatchNoOp)
              case decision of
                Dispatch.DispatchNoOp -> pure ()
                Dispatch.DispatchPrompt inferenceEnvelope -> do
                  maybeModelId <- ContextModelMap.lookupModelId contextModelMap contextIdValue
                  publishDispatchedInferenceRequest
                    transport
                    runtimeMode
                    requestTopic
                    (fromMaybe Text.empty maybeModelId)
                    inferenceEnvelope
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
  Text.Text ->
  Dispatch.InferenceRequestEnvelope ->
  IO ()
publishDispatchedInferenceRequest transport runtimeMode requestTopic resolvedModelId env = do
  let Contracts.ContextId contextIdText = Dispatch.inferenceContextId env
      Contracts.UserId userIdText = Dispatch.inferenceUserId env
      Contracts.MessageId promptMessageIdText = Dispatch.inferenceUserPromptMessageId env
      Contracts.ClientIdempotencyKey idempotencyKey = Dispatch.inferenceClientIdempotencyKey env
      protoPayload :: ProtoInference.InferenceRequest
      protoPayload =
        set (field @"requestId") promptMessageIdText
          . set (field @"requestModelId") resolvedModelId
          . set (field @"inputText") (Dispatch.inferencePromptText env)
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
-- 2. HTTP @GET@ the upstream @downloadUrl@ carried on the request
--    envelope (this is the only point in the supported daemon
--    topology that reaches the public internet).
-- 3. @PUT@ the downloaded bytes to MinIO under
--    @infernix-models/<modelId>/payload@ via a presigned PUT URL
--    minted from mounted @ClusterConfig.minio@ wiring and
--    @SecretsConfig.minio.credentialsPath@ credentials.
-- 4. @PUT@ the @.ready@ sentinel last so partial uploads are not
--    visible to engines (the engine helper waits on this sentinel).
-- 5. Publish a 'ModelBootstrapReadyEvent' on the matching ready topic
--    and ack the original request.
--
-- Producer-side dedup on the request topic (keyed by @modelId@) and
-- the named Failover subscription together give exactly-once
-- semantics for the upstream download under concurrent retries.
runModelBootstrapLoop ::
  PulsarTransport ->
  ConversationTopic.TopicNamespace ->
  IO ()
runModelBootstrapLoop transport systemNamespace = do
  let requestTopic =
        ConversationTopic.modelBootstrapRequestTopicName systemNamespace
  topicRef <- requireTopicRef requestTopic
  let consumerName = Text.unpack BootstrapModels.bootstrapSubscriptionName <> "-consumer"
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
      manager <- newManager defaultManagerSettings
      now <- getCurrentTime
      sentinelPresent <- minioObjectExists presigned manager sentinelObject
      if sentinelPresent
        then publishBootstrapReadyEvent transport systemNamespace request
        else do
          downloadedBytes <-
            downloadUpstreamModel manager (BootstrapModels.bootstrapRequestDownloadUrl request)
          putMinioObject presigned manager now payloadObject downloadedBytes
          putMinioObject presigned manager now sentinelObject "ready\n"
          publishBootstrapReadyEvent transport systemNamespace request

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
      options =
        (defaultPublishOptions ("infernix-model-bootstrap-" <> modelId))
          { publishMessageKey = Just modelId
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

downloadUpstreamModel :: Manager -> Text.Text -> IO ByteString.ByteString
downloadUpstreamModel manager urlText = do
  request <- parseRequest (Text.unpack urlText)
  response <- httpLbs request manager
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
  pure (Lazy.toStrict (responseBody response))

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
  Paths ->
  RuntimeMode ->
  EngineCommandOverrideMap ->
  ProtoInference.InferenceRequest ->
  IO InferenceResult
publishedResultFromRequest paths runtimeMode overrides protoRequest = do
  domainResult <- executeInference paths runtimeMode overrides (protoRequestToDomain protoRequest)
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

decodeJsonText :: (FromJSON a) => String -> Text.Text -> IO a
decodeJsonText label rawValue =
  case eitherDecodeStrict' (TextEncoding.encodeUtf8 rawValue) of
    Left err -> ioError (userError ("failed to decode " <> label <> ":\n" <> err))
    Right decodedValue -> pure decodedValue

runPulsarWebSocketClient :: PulsarWebSocketBase -> String -> (WebSockets.Connection -> IO a) -> IO a
runPulsarWebSocketClient websocketBase =
  WebSockets.runClient (pulsarWsHost websocketBase) (pulsarWsPort websocketBase)

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

buildConsumerSocketPath :: PulsarWebSocketBase -> TopicRef -> String -> String -> String
buildConsumerSocketPath websocketBase topicRef subscriptionName consumerName =
  buildSocketPath
    websocketBase
    ("consumer/" <> renderTopicPath topicRef <> "/" <> subscriptionName)
    -- Phase 7 Sprint 7.7: @Shared@ subscription so the supported
    -- multi-replica coordinator + engine daemons can split the
    -- request and batch topics without contending on an exclusive
    -- subscription. Per-context exclusive ownership lives on the
    -- per-conversation Failover subscriptions the dispatcher creates
    -- (Sprint 7.6), not on the global request/batch topics.
    [ ("subscriptionType", "Shared"),
      ("subscriptionInitialPosition", "Earliest"),
      ("receiverQueueSize", "1"),
      ("consumerName", consumerName)
    ]

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
      inputText = view ProtoInferenceFields.inputText protoRequest
    }

domainResultToProto :: InferenceResult -> ProtoInference.InferenceResult
domainResultToProto resultValue =
  set (field @"requestId") (requestId resultValue) $
    set (field @"resultModelId") (resultModelId resultValue) $
      set (field @"matrixRowId") (resultMatrixRowId resultValue) $
        set (field @"runtimeMode") (runtimeModeId (resultRuntimeMode resultValue)) $
          set (field @"selectedEngine") (resultSelectedEngine resultValue) $
            set (field @"status") (status resultValue) $
              set (field @"payload") (resultPayloadToProto (payload resultValue)) $
                set (field @"createdAt") (Text.pack (show (createdAt resultValue))) $
                  set (field @"userId") (resultUserId resultValue) $
                    set (field @"contextId") (resultContextId resultValue) $
                      set (field @"causalRef") (resultCausalRef resultValue) defMessage

protoResultToDomain :: ProtoInference.InferenceResult -> Maybe InferenceResult
protoResultToDomain protoResult = do
  parsedRuntimeMode <- parseRuntimeMode (view ProtoInferenceFields.runtimeMode protoResult)
  parsedPayload <- protoPayloadToDomain (view ProtoInferenceFields.payload protoResult)
  pure
    InferenceResult
      { requestId = view ProtoInferenceFields.requestId protoResult,
        resultModelId = view ProtoInferenceFields.resultModelId protoResult,
        resultMatrixRowId = view ProtoInferenceFields.matrixRowId protoResult,
        resultRuntimeMode = parsedRuntimeMode,
        resultSelectedEngine = view ProtoInferenceFields.selectedEngine protoResult,
        status = view ProtoInferenceFields.status protoResult,
        payload = parsedPayload,
        createdAt = read (Text.unpack (view ProtoInferenceFields.createdAt protoResult)),
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
