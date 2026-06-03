{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, bracket, displayException, finally, try)
import Control.Monad (forM, forM_, when)
import Data.Aeson qualified as Aeson
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.ByteString.Lazy.Char8 qualified as LazyByteStringChar8
import Data.Char (isAsciiUpper)
import Data.List (find, isInfixOf, isPrefixOf, sort)
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing, mapMaybe, maybeToList)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import Infernix.Bootstrap.Models qualified as BootstrapModels
import Infernix.Cluster
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.Conversation.Topic qualified as ConversationTopic
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Models
  ( expectedDaemonLocationForRuntime,
    expectedInferenceExecutorLocationForRuntime,
    hostBatchTopicForMode,
    requestTopicsForMode,
    resultTopicForMode,
  )
import Infernix.Runtime.Pulsar
  ( RawTopicMessage,
    compactTopicAndWait,
    publishDemoClientMessage,
    publishInferenceRequest,
    publishModelBootstrapRequest,
    publishRawTopicPayload,
    rawTopicInferenceRequestPromptIds,
    rawTopicInferenceResultCausalRefs,
    rawTopicMessageId,
    rawTopicMessageKey,
    rawTopicMessagePayload,
    readNamespaceCompactionThreshold,
    readPublishedInferenceResultMaybe,
    readRawTopicPayloads,
    serviceReadinessMarkerPath,
  )
import Infernix.Types
import Infernix.Web.Contracts qualified as Contracts
import Network.Socket
  ( Family (AF_INET),
    SockAddr (SockAddrInet),
    Socket,
    SocketOption (ReuseAddr),
    SocketType (Stream),
    bind,
    close,
    defaultProtocol,
    listen,
    setSocketOption,
    socket,
    tupleToHostAddress,
  )
import System.Directory
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (BufferMode (LineBuffering), IOMode (WriteMode), hClose, hFlush, hSetBuffering, openFile, stdout)
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process
  ( CreateProcess (cwd, std_err, std_out),
    StdStream (UseHandle),
    createProcess,
    proc,
    readCreateProcessWithExitCode,
    readProcess,
    readProcessWithExitCode,
    terminateProcess,
    waitForProcess,
  )

data CompactedTopicMessage = CompactedTopicMessage
  { compactedTopicMessageKey :: Maybe Text.Text,
    compactedTopicMessagePayload :: ByteString.ByteString
  }
  deriving (Eq, Show)

main :: IO ()
main = do
  integrationTestRoot <- testRootPath "integration"
  withTestRoot integrationTestRoot $ do
    paths <- Config.discoverPaths
    runtimeModes <- integrationRuntimeModes
    mapM_ (exerciseRuntimeMode paths) runtimeModes
    when (LinuxCpu `elem` runtimeModes) $ do
      validateDemoUiDisabled paths LinuxCpu
    case runtimeModes of
      runtimeMode : _
        | Config.controlPlaneContext paths /= Config.OuterContainer ->
            validateEdgePortConflictAndRediscovery paths runtimeMode
      _ -> pure ()
    putStrLn "integration tests passed"

integrationRuntimeModes :: IO [RuntimeMode]
integrationRuntimeModes =
  (: []) <$> Config.resolveRuntimeMode Nothing

withClusterLifecycle :: RuntimeMode -> IO a -> IO a
withClusterLifecycle runtimeMode action =
  ( do
      clusterUp (Just runtimeMode)
      action
  )
    `finally` clusterDown (Just runtimeMode)

exerciseRuntimeMode :: Paths -> RuntimeMode -> IO ()
exerciseRuntimeMode paths runtimeMode = do
  materializeGeneratedSubstrate runtimeMode True
  withClusterLifecycle runtimeMode $ do
    withRuntimeServiceDaemonIfNeeded paths runtimeMode $ do
      reportStep ("cluster state reload: " <> showRuntimeMode runtimeMode)
      maybeState <- loadClusterState paths
      state <- maybe (fail "cluster state was not available after cluster up") pure maybeState
      reportStep ("demo config decode: " <> showRuntimeMode runtimeMode)
      demoConfig <- decodeDemoConfigFile (generatedDemoConfigPath state)
      reportStep ("demo config loaded: " <> showRuntimeMode runtimeMode)
      representativeModelId <-
        case map (Text.unpack . modelId) (models demoConfig) of
          modelIdValue : _ -> pure modelIdValue
          [] -> fail "generated demo config did not publish any models"
      let activeModels = models demoConfig
          activeModelIds = map (Text.unpack . modelId) activeModels
          expectedDaemonLocation = Text.unpack (expectedDaemonLocationForRuntime runtimeMode)
          expectedInferenceExecutorLocation = Text.unpack (expectedInferenceExecutorLocationForRuntime runtimeMode)
          expectedDispatchMode = expectedInferenceDispatchMode runtimeMode
      assert (clusterPresent state) ("cluster up records cluster presence for " <> showRuntimeMode runtimeMode)
      assertClusterServiceDeployment state
      let baseUrl = routeBaseUrl paths state
      reportStep ("route probes: " <> showRuntimeMode runtimeMode)
      homeResponse <- httpGet (baseUrl <> "/")
      publicationResponse <- httpGet (baseUrl <> "/api/publication")
      demoConfigResponse <- httpGet (baseUrl <> "/api/demo-config")
      routedDemoConfig <- requireJsonDemoConfig demoConfigResponse
      modelsResponse <- httpGet (baseUrl <> "/api/models")
      harborResponse <- httpGet (baseUrl <> "/harbor")
      (harborApiStatus, harborApiResponse) <- httpGetWithStatus (baseUrl <> "/harbor/api/v2.0/projects")
      -- Phase 3 Sprint 3.11 (2026-05-30): the standalone MinIO Console
      -- Deployment was retired together with the bitnami sub-chart;
      -- the `/minio/console` route is gone and operators reach
      -- artifacts through presigned MinIO URLs minted by the demo
      -- backend instead.
      (minioS3Status, minioS3Response) <- httpGetWithStatus (baseUrl <> "/minio/s3/models/demo.bin")
      pulsarAdminResponse <- httpGet (baseUrl <> "/pulsar/admin/admin/v2/clusters")
      (pulsarHttpStatus, _) <- httpGetWithStatus (baseUrl <> "/pulsar/ws/v2/producer/public/default/demo")
      assert ("Infernix" `isInfixOf` homeResponse) "demo root serves the browser entrypoint"
      assert (("\"runtimeMode\": \"" <> showRuntimeMode runtimeMode <> "\"") `isInfixOf` publicationResponse) "publication reports the active runtime mode"
      assert ("\"clusterpresent\": true" `isInfixOf` mapToLowerAscii publicationResponse) "publication reports cluster presence"
      assert
        (("\"inferenceDispatchMode\":\"" <> expectedDispatchMode <> "\"") `isInfixOf` compact publicationResponse)
        "publication reports the runtime-specific inference dispatch mode"
      assert
        (("\"daemonLocation\":\"" <> expectedDaemonLocation <> "\"") `isInfixOf` compact publicationResponse)
        "publication reports the cluster daemon location"
      assert
        (("\"inferenceExecutorLocation\":\"" <> expectedInferenceExecutorLocation <> "\"") `isInfixOf` compact publicationResponse)
        "publication reports the substrate-specific inference executor location"
      assertHostBatchPublication runtimeMode publicationResponse
      assert ("\"demo_ui\":true" `isInfixOf` compact demoConfigResponse) "demo config reports the enabled demo UI flag"
      assert (activeDaemonRole routedDemoConfig == Coordinator) "cluster-mounted demo config reports the coordinator role"
      assertRoutedDaemonSplit runtimeMode routedDemoConfig
      assert
        ( ("\"request_topics\":[\"persistent://infernix/demo/inference.request." <> showRuntimeMode runtimeMode <> "\"]")
            `isInfixOf` compact demoConfigResponse
        )
        "demo config reports the active request topic"
      assert
        ( ("\"result_topic\":\"persistent://infernix/demo/inference.result." <> showRuntimeMode runtimeMode <> "\"")
            `isInfixOf` compact demoConfigResponse
        )
        "demo config reports the active result topic"
      assert ("\"engines\":[" `isInfixOf` compact demoConfigResponse) "demo config reports engine bindings"
      assert ("\"adapterEntrypoint\":\"" `isInfixOf` compact demoConfigResponse) "demo config publishes adapter entrypoints"
      assert ("\"projectDirectory\":\"python\"" `isInfixOf` compact demoConfigResponse) "demo config publishes the shared Python project directory"
      assert ("\"modelId\"" `isInfixOf` modelsResponse) "model listing returns JSON models"
      assert
        (all (\modelIdValue -> ("\"modelId\":\"" <> modelIdValue <> "\"") `isInfixOf` compact modelsResponse) activeModelIds)
        "model listing returns every generated active-mode catalog entry"
      assert ("Harbor" `isInfixOf` harborResponse) "harbor route is published"
      assert
        (harborApiStatus == 200 && "\"name\":\"library\"" `isInfixOf` compact harborApiResponse)
        "harbor API routes strip the /harbor prefix and reach the live Harbor project API on the cluster path"
      assert
        (minioS3Status `elem` [200, 401, 403, 404] && "\"rewrittenPath\"" `notElemString` compact minioS3Response)
        "minio S3 route stays published and reaches the live MinIO S3 upstream on the cluster path"
      assert
        ("[\"infernix-infernix-pulsar\"]" `isInfixOf` compact pulsarAdminResponse)
        "pulsar admin routes preserve the upstream admin/v2 context root"
      assert
        (pulsarHttpStatus == 405)
        "pulsar HTTP routes preserve the websocket context root and reach the real servlet on the cluster path"
      reportStep ("per-model inference: " <> showRuntimeMode runtimeMode)
      forM_ activeModelIds (validateCatalogModelInference paths runtimeMode)
      reportStep ("cache lifecycle: " <> showRuntimeMode runtimeMode)
      -- Phase 7 Sprint 7.7 follow-on (May 26, 2026): the legacy
      -- single-binary cache assertions assumed @/api/cache@ on the
      -- @infernix-demo@ pod could observe every model the engine pod
      -- has cached. After the supported daemon split (Sprint 7.7),
      -- the demo pod runs no inference and its
      -- @modelCacheRoot@-derived manifest listing is empty for
      -- routed cluster runs. The supported integration assertion is
      -- now "the cache endpoint is published, reachable, and
      -- returns a JSON array (possibly empty)".
      cacheResponse <- httpGet (baseUrl <> "/api/cache")
      assert
        ("[" `isInfixOf` compact cacheResponse)
        "cache status endpoint returns a JSON array (the engine-pod manifest contents are not visible from the demo pod after the daemon split)"

      reportStep ("service runtime loop: " <> showRuntimeMode runtimeMode)
      validateServiceRuntimeLoop paths runtimeMode representativeModelId

      reportStep ("durable Pulsar topic families: " <> showRuntimeMode runtimeMode)
      validateDurableTopicFamilyRoundTrips paths runtimeMode representativeModelId

      -- Phase 7 Sprint 7.14 (2026-05-31): Apple engine.lock enforcement
      -- chaos case. The chart-driven Linux engine pods rely on required
      -- pod anti-affinity to prove one-engine-per-node; the Apple
      -- host-native engine relies on the @engine.lock@ flock contract in
      -- `Infernix.Service.acquireEngineLock`. The first host daemon is
      -- already spawned by `withRuntimeServiceDaemonIfNeeded` above and
      -- holds the lock; this case validates that a second spawn exits
      -- non-zero with the named diagnostic.
      when (requiresHostServiceHarness paths runtimeMode) $ do
        reportStep ("apple engine.lock enforcement: " <> showRuntimeMode runtimeMode)
        validateAppleEngineLockEnforcement paths

      when (runtimeMode == LinuxCpu) $ do
        reportStep "frontend pod replacement preserves durable state"
        validateFrontendPodReplacementPreservesDurableState paths state runtimeMode representativeModelId
        reportStep "coordinator failover preserves durable prompt dispatch"
        validateCoordinatorFailoverDurablePrompt paths state runtimeMode representativeModelId
        reportStep "engine pod replacement preserves durable prompt result"
        validateEnginePodReplacementDurablePrompt paths state runtimeMode representativeModelId
        reportStep "engine node drain preserves durable prompt result"
        validateEngineNodeDrainDurablePrompt paths state runtimeMode representativeModelId
        reportStep "model bootstrap failover and deduplication"
        validateModelBootstrapDeduplication paths state runtimeMode
        reportStep "multi-user durable prompt throughput"
        validateMultiUserDurablePromptThroughput paths runtimeMode representativeModelId
        reportStep "harbor recovery"
        validateHarborRecovery state
        reportStep "minio durability"
        validateMinioDurability state
        reportStep "routed pulsar recovery"
        validateRoutedPulsarRecovery paths state runtimeMode activeModelIds
        reportStep "postgres failover"
        validatePostgresFailover state
        reportStep "postgres lifecycle rebinding"
        validatePostgresLifecycleRebinding paths runtimeMode state
        -- Phase 7 Sprint 7.14 (2026-05-31): Linux engine
        -- one-engine-per-node enforcement. The chart deploys
        -- `infernix-engine` with `requiredDuringSchedulingIgnoredDuringExecution`
        -- pod anti-affinity keyed by hostname; scaling the deployment
        -- past the available engine-capable node count must leave the
        -- extra replica `Pending` with the anti-affinity rejection
        -- message in its scheduler events. The Apple-host equivalent
        -- (the `engine.lock` flock) is covered by
        -- `validateAppleEngineLockEnforcement` above.
        reportStep "linux engine anti-affinity enforcement"
        validateLinuxEngineAntiAffinityEnforcement state

      statusOutput <- captureInfernixOutput ["cluster", "status"]
      assert ("clusterPresent: True" `isInfixOf` statusOutput) "cluster status reports the cluster presence"
      assert (("runtimeMode: " <> showRuntimeMode runtimeMode) `isInfixOf` statusOutput) "cluster status reports the runtime mode"
      assert ("lifecycleStatus: idle" `isInfixOf` statusOutput) "cluster status reports idle lifecycle state after successful reconcile"
      assert (("publicationInferenceDispatchMode: " <> expectedDispatchMode) `isInfixOf` statusOutput) "cluster status reports the inference dispatch mode"
      assertHostBatchStatus runtimeMode statusOutput
      assert ("publicationStatePath: " `isInfixOf` statusOutput) "cluster status reports the publication state path"
      assert ("kubernetesNodeCount: 0" `notElemString` statusOutput) "cluster status reports reachable Kubernetes nodes"
      assert ("kubernetesPodCount: 0" `notElemString` statusOutput) "cluster status reports reachable Kubernetes pods"

  maybeDownState <- loadClusterState paths
  assert (maybe False (not . clusterPresent) maybeDownState) "cluster down records cluster absence"
  downStatusOutput <- captureInfernixOutput ["cluster", "status"]
  assert ("clusterPresent: False" `isInfixOf` downStatusOutput) "cluster status reports cluster absence after down"
  assert ("lifecyclePhase: cluster-absent" `isInfixOf` downStatusOutput) "cluster status reports the idle absent lifecycle phase after down"

validateCatalogModelInference :: Paths -> RuntimeMode -> String -> IO ()
validateCatalogModelInference paths runtimeMode modelIdValue = do
  requestTopic <-
    case requestTopicsForMode runtimeMode of
      topic : _ -> pure topic
      [] -> fail ("no request topics configured for " <> showRuntimeMode runtimeMode)
  let resultTopic = resultTopicForMode runtimeMode
  requestIdValue <-
    publishInferenceRequest
      paths
      runtimeMode
      requestTopic
      InferenceRequest
        { requestModelId = Text.pack modelIdValue,
          inputText = Text.pack ("integration coverage for " <> modelIdValue)
        }
  maybeResult <- waitForPublishedResult paths runtimeMode resultTopic requestIdValue
  case maybeResult of
    Nothing -> fail ("service daemon did not publish a result for " <> modelIdValue)
    Just resultValue -> do
      assert
        (resultModelId resultValue == Text.pack modelIdValue)
        ("inference returns the selected model id for " <> modelIdValue)
      assert
        (resultRuntimeMode resultValue == runtimeMode)
        ("service daemon preserves the runtime mode in published results for " <> modelIdValue)

assertHostBatchPublication :: RuntimeMode -> String -> IO ()
assertHostBatchPublication runtimeMode publicationResponse =
  maybe assertNoHostBatch assertHostBatch (hostBatchTopicForMode runtimeMode)
  where
    assertNoHostBatch =
      assert
        ("\"hostInferenceBatchTopic\":null" `isInfixOf` compact publicationResponse)
        ("publication reports no host inference batch topic for " <> showRuntimeMode runtimeMode)

    assertHostBatch topic =
      assert
        (("\"hostInferenceBatchTopic\":\"" <> Text.unpack topic <> "\"") `isInfixOf` compact publicationResponse)
        ("publication reports the configured inference batch handoff topic for " <> showRuntimeMode runtimeMode)

assertHostBatchStatus :: RuntimeMode -> String -> IO ()
assertHostBatchStatus runtimeMode statusOutput =
  mapM_ assertHostBatch (hostBatchTopicForMode runtimeMode)
  where
    assertHostBatch topic =
      assert
        (("publicationHostInferenceBatchTopic: " <> Text.unpack topic) `isInfixOf` statusOutput)
        ("cluster status reports the inference batch handoff topic for " <> showRuntimeMode runtimeMode)

assertRoutedDaemonSplit :: RuntimeMode -> DemoConfig -> IO ()
assertRoutedDaemonSplit runtimeMode routedDemoConfig = do
  assert (daemonConfigRole (coordinatorDaemon routedDemoConfig) == Coordinator) "demo config reports coordinator metadata"
  assert
    (daemonConfigRequestTopics (coordinatorDaemon routedDemoConfig) == requestTopicsForMode runtimeMode)
    "coordinator consumes the substrate request topic"
  assert
    (daemonConfigHostBatchTopic (coordinatorDaemon routedDemoConfig) == hostBatchTopicForMode runtimeMode)
    "coordinator publishes the configured inference batch handoff topic"
  maybe
    (fail ("demo config omits engine metadata for " <> showRuntimeMode runtimeMode))
    assertEngineConfig
    (engineDaemon routedDemoConfig)
  where
    assertEngineConfig engineConfig = do
      assert (daemonConfigRole engineConfig == Engine) "demo config reports engine metadata"
      assert
        (daemonConfigRequestTopics engineConfig == maybeToList (hostBatchTopicForMode runtimeMode))
        "engine consumes the configured inference batch handoff topic"
      assert
        (isNothing (daemonConfigHostBatchTopic engineConfig))
        "engine does not forward its own inference batch topic"

assertClusterServiceDeployment :: ClusterState -> IO ()
assertClusterServiceDeployment state = do
  deploymentName <-
    trim
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "deployment",
          "infernix-coordinator",
          "-o",
          "jsonpath={.metadata.name}"
        ]
  assert (deploymentName == "infernix-coordinator") "cluster deploys the supported daemon-split coordinator on every substrate"
  serviceSessionAffinity <-
    trim
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "service",
          "infernix-demo",
          "-o",
          "jsonpath={.spec.sessionAffinity}"
        ]
  assert
    (serviceSessionAffinity == "None")
    "demo Service disables Kubernetes session affinity so any stateless frontend replica can host WebSocket sessions"

validateServiceRuntimeLoop :: Paths -> RuntimeMode -> String -> IO ()
validateServiceRuntimeLoop paths runtimeMode representativeModelId = do
  requestTopic <-
    case requestTopicsForMode runtimeMode of
      topic : _ -> pure topic
      [] -> fail ("no request topics configured for " <> showRuntimeMode runtimeMode)
  let resultTopic = resultTopicForMode runtimeMode
  requestIdValue <-
    publishInferenceRequest
      paths
      runtimeMode
      requestTopic
      InferenceRequest
        { requestModelId = Text.pack representativeModelId,
          inputText = "service daemon request path"
        }
  maybeResult <- waitForPublishedResult paths runtimeMode resultTopic requestIdValue
  case maybeResult of
    Nothing -> fail ("service daemon did not publish a result for " <> showRuntimeMode runtimeMode)
    Just resultValue -> do
      assert (resultModelId resultValue == Text.pack representativeModelId) "service daemon publishes the selected model id"
      assert (resultRuntimeMode resultValue == runtimeMode) "service daemon preserves the runtime mode in published results"

validateDurableTopicFamilyRoundTrips :: Paths -> RuntimeMode -> String -> IO ()
validateDurableTopicFamilyRoundTrips paths runtimeMode representativeModelId = do
  runToken <- integrationRunToken
  let namespace = ConversationTopic.defaultDemoTopicNamespace
      systemNamespace = ConversationTopic.systemTopicNamespace
      runtimeText = runtimeModeId runtimeMode
      tokenText = Text.pack runToken
      userIdValue = Contracts.UserId ("integration-user-" <> runtimeText <> "-" <> tokenText)
      contextIdValue = Contracts.ContextId ("integration-context-" <> runtimeText <> "-" <> tokenText)
      contextIdText = Contracts.unContextId contextIdValue
      modelIdText = Text.pack representativeModelId
      contextTopic = ConversationTopic.contextsMetadataTopicName namespace userIdValue
      draftsTopic = ConversationTopic.draftsMetadataTopicName namespace userIdValue
      conversationTopic = ConversationTopic.conversationTopicName namespace userIdValue contextIdValue
      bootstrapModelId = "integration-bootstrap-" <> runtimeText <> "-" <> tokenText
      bootstrapReadyTopic =
        ConversationTopic.modelBootstrapReadyTopicName systemNamespace bootstrapModelId
      createdEvent =
        Contracts.ContextCreated
          { Contracts.contextCreatedContextId = contextIdValue,
            Contracts.contextCreatedModelId = modelIdText,
            Contracts.contextCreatedTitle = "Integration Roundtrip"
          }
      draftEvent = Contracts.DraftUpdated contextIdValue "draft from integration"
      cancelEvent =
        Contracts.ConversationCancelEvent
          ( Contracts.ConversationCancelPayload
              (Contracts.MessageId ("prompt-for-cancel-" <> runtimeText))
          )
      bootstrapReadyEvent =
        BootstrapModels.ModelBootstrapReadyEvent
          { BootstrapModels.readyEventModelId = bootstrapModelId,
            BootstrapModels.readyEventReadyAtIso8601 = "2026-05-28T00:00:00Z"
          }

  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    userIdValue
    (Contracts.ClientCreateContext contextIdValue modelIdText "Integration Roundtrip")
  contextMessages <- waitForRawTopicMessages paths runtimeMode contextTopic 1
  assertTopicMessageKey contextMessages (Just contextIdText) "contexts metadata topic carries the context id as the Pulsar message key"
  assertTopicHasDecoded contextMessages createdEvent "contexts metadata topic round-trips the ContextCreated event"

  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    userIdValue
    (Contracts.ClientUpdateDraft contextIdValue "draft from integration")
  draftMessages <- waitForRawTopicMessages paths runtimeMode draftsTopic 1
  assertTopicMessageKey draftMessages (Just contextIdText) "drafts topic carries the context id as the Pulsar message key"
  assertTopicHasDecoded draftMessages draftEvent "drafts topic round-trips the DraftUpdated event"

  validateCompactedTopicBrokerBehavior paths runtimeMode modelIdText tokenText
  validateProducerDeduplicationBehavior paths runtimeMode tokenText
  validateDurableContextPromptRoundTrip paths runtimeMode modelIdText tokenText

  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    userIdValue
    (Contracts.ClientCancelPrompt contextIdValue (Contracts.MessageId ("prompt-for-cancel-" <> runtimeText)))
  conversationMessages <- waitForRawTopicMessages paths runtimeMode conversationTopic 1
  assertTopicMessageKey conversationMessages Nothing "conversation log topic remains append-only without a compaction key"
  assertTopicHasDecoded conversationMessages cancelEvent "conversation topic round-trips the ConversationCancelEvent"

  publishRawTopicPayload
    paths
    runtimeMode
    Nothing
    bootstrapReadyTopic
    ("integration-bootstrap-" <> runtimeText)
    (Just bootstrapModelId)
    bootstrapModelId
    (LazyByteString.toStrict (Aeson.encode bootstrapReadyEvent))
  bootstrapMessages <- waitForRawTopicMessages paths runtimeMode bootstrapReadyTopic 1
  assertTopicMessageKey bootstrapMessages (Just bootstrapModelId) "model-bootstrap ready topic carries the model id as the Pulsar message key"
  assertTopicHasDecoded bootstrapMessages bootstrapReadyEvent "model-bootstrap ready topic round-trips the ready event"

integrationRunToken :: IO String
integrationRunToken = do
  now <- getPOSIXTime
  pure (show (floor (now * 1000000) :: Integer))

data DurablePromptContext = DurablePromptContext
  { durablePromptUserId :: Contracts.UserId,
    durablePromptContextId :: Contracts.ContextId,
    durablePromptConversationTopic :: Text.Text,
    durablePromptToken :: Text.Text
  }
  deriving (Eq, Show)

data DurablePromptRef = DurablePromptRef
  { durablePromptRefContext :: DurablePromptContext,
    durablePromptRefMessageId :: Contracts.MessageId,
    durablePromptRefStartedAt :: Double
  }
  deriving (Eq, Show)

data PromptPipelineCounts = PromptPipelineCounts
  { promptPipelineRequestCount :: Int,
    promptPipelineBatchCount :: Int,
    promptPipelineResultCount :: Int,
    promptPipelineConversationResultCount :: Int
  }
  deriving (Eq, Show)

createDurablePromptContext :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO DurablePromptContext
createDurablePromptContext paths runtimeMode modelIdText label = do
  runToken <- Text.pack <$> integrationRunToken
  let namespace = ConversationTopic.defaultDemoTopicNamespace
      runtimeText = runtimeModeId runtimeMode
      userIdValue = Contracts.UserId ("chaos-user-" <> label <> "-" <> runtimeText <> "-" <> runToken)
      contextIdValue = Contracts.ContextId ("chaos-context-" <> label <> "-" <> runToken)
      conversationTopic = ConversationTopic.conversationTopicName namespace userIdValue contextIdValue
      contextsTopic = ConversationTopic.contextsMetadataTopicName namespace userIdValue
      warmupPrompt = Contracts.MessageId ("warmup-" <> label <> "-" <> runToken)
  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    userIdValue
    (Contracts.ClientCreateContext contextIdValue modelIdText ("Chaos " <> label))
  _ <- waitForRawTopicMessages paths runtimeMode contextsTopic 1
  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    userIdValue
    (Contracts.ClientCancelPrompt contextIdValue warmupPrompt)
  _ <- waitForRawTopicMessages paths runtimeMode conversationTopic 1
  pure
    DurablePromptContext
      { durablePromptUserId = userIdValue,
        durablePromptContextId = contextIdValue,
        durablePromptConversationTopic = conversationTopic,
        durablePromptToken = runToken
      }

waitForDispatcherDiscovery :: IO ()
waitForDispatcherDiscovery =
  threadDelay 35000000

submitDurablePrompt :: Paths -> RuntimeMode -> DurablePromptContext -> Text.Text -> IO DurablePromptRef
submitDurablePrompt paths runtimeMode context label = do
  startedAt <- realToFrac <$> getPOSIXTime
  let promptTextValue =
        "durable chaos prompt "
          <> label
          <> " "
          <> durablePromptToken context
      promptPayload =
        Contracts.UserPromptPayload
          { Contracts.promptText = promptTextValue,
            Contracts.promptClientIdempotencyKey =
              Contracts.ClientIdempotencyKey
                ("prompt-idem-" <> label <> "-" <> durablePromptToken context),
            Contracts.promptUserUploads = []
          }
  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    (durablePromptUserId context)
    (Contracts.ClientSubmitPrompt (durablePromptContextId context) promptPayload)
  promptMessageId <-
    waitForConversationPromptMessageId
      paths
      runtimeMode
      (durablePromptConversationTopic context)
      promptTextValue
  pure
    DurablePromptRef
      { durablePromptRefContext = context,
        durablePromptRefMessageId = promptMessageId,
        durablePromptRefStartedAt = startedAt
      }

waitForConversationPromptMessageId :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO Contracts.MessageId
waitForConversationPromptMessageId paths runtimeMode conversationTopic promptTextValue = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail ("timed out waiting for conversation prompt event on " <> Text.unpack conversationTopic)
      | otherwise = do
          messages <- readRawTopicPayloads paths runtimeMode Nothing conversationTopic 128
          case conversationPromptMessageIds promptTextValue messages of
            promptId : _ -> pure promptId
            [] -> do
              threadDelay 500000
              go (remainingAttempts - 1)

conversationPromptMessageIds :: Text.Text -> [RawTopicMessage] -> [Contracts.MessageId]
conversationPromptMessageIds promptTextValue messages =
  [ Contracts.MessageId (rawTopicMessageId rawMessage)
  | rawMessage <- messages,
    Right (Contracts.ConversationUserPromptEvent payload) <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)],
    Contracts.promptText payload == promptTextValue
  ]

waitForConversationResultPayloadForPrompt :: Paths -> RuntimeMode -> Text.Text -> Contracts.MessageId -> IO Contracts.ConversationInferenceResultPayload
waitForConversationResultPayloadForPrompt paths runtimeMode conversationTopic promptMessageId = go (180 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail
            ( "timed out waiting for durable-context inference result for "
                <> Text.unpack (Contracts.unMessageId promptMessageId)
                <> " on "
                <> Text.unpack conversationTopic
            )
      | otherwise = do
          messages <- readRawTopicPayloads paths runtimeMode Nothing conversationTopic 256
          case conversationResultPayloadsForPrompt promptMessageId messages of
            resultPayload : _ -> pure resultPayload
            [] -> do
              threadDelay 1000000
              go (remainingAttempts - 1)

conversationResultPayloadsForPrompt :: Contracts.MessageId -> [RawTopicMessage] -> [Contracts.ConversationInferenceResultPayload]
conversationResultPayloadsForPrompt promptMessageId messages =
  [ resultPayload
  | rawMessage <- messages,
    Right (Contracts.ConversationInferenceResultEvent resultPayload) <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)],
    Contracts.inferenceResultUserPromptMessageId resultPayload == promptMessageId
  ]

waitForPromptPipelineCounts :: Paths -> RuntimeMode -> DurablePromptRef -> IO PromptPipelineCounts
waitForPromptPipelineCounts paths runtimeMode promptRef = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail ("timed out waiting for prompt pipeline counts for " <> Text.unpack promptIdText)
      | otherwise = do
          counts <- readPromptPipelineCounts paths runtimeMode promptRef
          if promptPipelineComplete counts
            then do
              threadDelay 2000000
              readPromptPipelineCounts paths runtimeMode promptRef
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)
    promptIdText = Contracts.unMessageId (durablePromptRefMessageId promptRef)
    promptPipelineComplete counts =
      promptPipelineRequestCount counts >= 1
        && maybe True (const (promptPipelineBatchCount counts >= 1)) (hostBatchTopicForMode runtimeMode)
        && promptPipelineResultCount counts >= 1
        && promptPipelineConversationResultCount counts >= 1

readPromptPipelineCounts :: Paths -> RuntimeMode -> DurablePromptRef -> IO PromptPipelineCounts
readPromptPipelineCounts paths runtimeMode promptRef = do
  requestTopic <-
    case requestTopicsForMode runtimeMode of
      topic : _ -> pure topic
      [] -> fail ("no request topic configured for " <> showRuntimeMode runtimeMode)
  let promptIdText = Contracts.unMessageId (durablePromptRefMessageId promptRef)
      resultTopic = resultTopicForMode runtimeMode
      conversationTopic = durablePromptConversationTopic (durablePromptRefContext promptRef)
  requestMessages <- readRawTopicPayloads paths runtimeMode Nothing requestTopic 1024
  batchMessages <-
    case hostBatchTopicForMode runtimeMode of
      Nothing -> pure []
      Just batchTopic -> readRawTopicPayloads paths runtimeMode Nothing batchTopic 1024
  resultMessages <- readRawTopicPayloads paths runtimeMode Nothing resultTopic 1024
  conversationMessages <- readRawTopicPayloads paths runtimeMode Nothing conversationTopic 256
  pure
    PromptPipelineCounts
      { promptPipelineRequestCount =
          length
            [ ()
            | requestPromptId <- rawTopicInferenceRequestPromptIds requestMessages,
              requestPromptId == promptIdText
            ],
        promptPipelineBatchCount =
          length
            [ ()
            | requestPromptId <- rawTopicInferenceRequestPromptIds batchMessages,
              requestPromptId == promptIdText
            ],
        promptPipelineResultCount =
          length
            [ ()
            | resultCausalRef <- rawTopicInferenceResultCausalRefs resultMessages,
              resultCausalRef == promptIdText
            ],
        promptPipelineConversationResultCount =
          length (conversationResultPayloadsForPrompt (durablePromptRefMessageId promptRef) conversationMessages)
      }

assertPromptPipelineExactlyOnce :: Paths -> RuntimeMode -> DurablePromptRef -> IO ()
assertPromptPipelineExactlyOnce paths runtimeMode promptRef = do
  counts <- waitForPromptPipelineCounts paths runtimeMode promptRef
  assert
    (promptPipelineRequestCount counts == 1)
    ("exactly one inference request is published for " <> Text.unpack promptIdText <> ": " <> show counts)
  case hostBatchTopicForMode runtimeMode of
    Nothing -> pure ()
    Just _ ->
      assert
        (promptPipelineBatchCount counts == 1)
        ("exactly one inference batch is published for " <> Text.unpack promptIdText <> ": " <> show counts)
  assert
    (promptPipelineResultCount counts == 1)
    ("exactly one inference result is published for " <> Text.unpack promptIdText <> ": " <> show counts)
  assert
    (promptPipelineConversationResultCount counts == 1)
    ("exactly one conversation result is written for " <> Text.unpack promptIdText <> ": " <> show counts)
  where
    promptIdText = Contracts.unMessageId (durablePromptRefMessageId promptRef)

assertCompletedResultPayload :: Contracts.ConversationInferenceResultPayload -> String -> IO ()
assertCompletedResultPayload resultPayload message =
  assert
    (Contracts.inferenceResultStatus resultPayload == "completed")
    (message <> ": " <> show resultPayload)

validateFrontendPodReplacementPreservesDurableState :: Paths -> ClusterState -> RuntimeMode -> String -> IO ()
validateFrontendPodReplacementPreservesDurableState paths state runtimeMode representativeModelId = do
  waitForDeploymentReadyReplicasAtLeast state "infernix-demo" 2
  context <- createDurablePromptContext paths runtimeMode (Text.pack representativeModelId) "frontend"
  let draftsTopic = ConversationTopic.draftsMetadataTopicName ConversationTopic.defaultDemoTopicNamespace (durablePromptUserId context)
      draftText = "draft survives frontend pod replacement " <> durablePromptToken context
      draftEvent = Contracts.DraftUpdated (durablePromptContextId context) draftText
  publishDemoClientMessage
    paths
    runtimeMode
    Nothing
    (durablePromptUserId context)
    (Contracts.ClientUpdateDraft (durablePromptContextId context) draftText)
  draftMessages <- waitForRawTopicMessages paths runtimeMode draftsTopic 1
  assertTopicHasDecoded draftMessages draftEvent "draft event is durable before frontend replacement"
  oldPod <- requirePodByPrefix state "platform" "infernix-demo-"
  runKubectl state ["-n", "platform", "delete", "pod", oldPod]
  waitForRollout state "deployment/infernix-demo"
  _ <- waitForPodByPrefix state "platform" "infernix-demo-" (Just oldPod)
  let baseUrl = routeBaseUrl paths state
  _ <- httpGet (baseUrl <> "/api/demo-config")
  durableDraftMessages <- waitForRawTopicMessages paths runtimeMode draftsTopic 1
  assertTopicHasDecoded durableDraftMessages draftEvent "draft event remains readable after frontend replacement"
  waitForDispatcherDiscovery
  promptRef <- submitDurablePrompt paths runtimeMode context "frontend-post-replacement"
  resultPayload <-
    waitForConversationResultPayloadForPrompt
      paths
      runtimeMode
      (durablePromptConversationTopic context)
      (durablePromptRefMessageId promptRef)
  assertCompletedResultPayload resultPayload "durable prompt still completes after frontend pod replacement"
  assertPromptPipelineExactlyOnce paths runtimeMode promptRef

validateCoordinatorFailoverDurablePrompt :: Paths -> ClusterState -> RuntimeMode -> String -> IO ()
validateCoordinatorFailoverDurablePrompt paths state runtimeMode representativeModelId = do
  waitForDeploymentReadyReplicasAtLeast state "infernix-coordinator" 2
  context <- createDurablePromptContext paths runtimeMode (Text.pack representativeModelId) "coordinator"
  waitForDispatcherDiscovery
  promptRef <- submitDurablePrompt paths runtimeMode context "coordinator-failover"
  oldPod <- requirePodByPrefix state "platform" "infernix-coordinator-"
  runKubectl state ["-n", "platform", "delete", "pod", oldPod]
  waitForRollout state "deployment/infernix-coordinator"
  _ <- waitForPodByPrefix state "platform" "infernix-coordinator-" (Just oldPod)
  resultPayload <-
    waitForConversationResultPayloadForPrompt
      paths
      runtimeMode
      (durablePromptConversationTopic context)
      (durablePromptRefMessageId promptRef)
  assertCompletedResultPayload resultPayload "durable prompt completes through coordinator pod replacement"
  assertPromptPipelineExactlyOnce paths runtimeMode promptRef

validateEnginePodReplacementDurablePrompt :: Paths -> ClusterState -> RuntimeMode -> String -> IO ()
validateEnginePodReplacementDurablePrompt paths state runtimeMode representativeModelId = do
  waitForDeploymentReadyReplicasAtLeast state "infernix-engine" 2
  context <- createDurablePromptContext paths runtimeMode (Text.pack representativeModelId) "engine"
  waitForDispatcherDiscovery
  promptRef <- submitDurablePrompt paths runtimeMode context "engine-replacement"
  oldPod <- requirePodByPrefix state "platform" "infernix-engine-"
  runKubectl state ["-n", "platform", "delete", "pod", oldPod]
  waitForRollout state "deployment/infernix-engine"
  _ <- waitForPodByPrefix state "platform" "infernix-engine-" (Just oldPod)
  resultPayload <-
    waitForConversationResultPayloadForPrompt
      paths
      runtimeMode
      (durablePromptConversationTopic context)
      (durablePromptRefMessageId promptRef)
  assertCompletedResultPayload resultPayload "durable prompt completes through engine pod replacement"
  assertPromptPipelineExactlyOnce paths runtimeMode promptRef

validateEngineNodeDrainDurablePrompt :: Paths -> ClusterState -> RuntimeMode -> String -> IO ()
validateEngineNodeDrainDurablePrompt paths state runtimeMode representativeModelId = do
  waitForDeploymentReadyReplicasAtLeast state "infernix-engine" 2
  (_, nodeName) <- requireReadyEnginePodNode state
  let restore =
        runKubectl state ["uncordon", nodeName]
          >> waitForDeploymentReadyReplicasAtLeast state "infernix-engine" 2
          >> waitForDeploymentReadyReplicasAtLeast state "infernix-coordinator" 2
          >> waitForDeploymentReadyReplicasAtLeast state "infernix-demo" 2
  ( do
      runKubectl
        state
        [ "drain",
          nodeName,
          "--ignore-daemonsets",
          "--delete-emptydir-data",
          "--force",
          "--timeout=180s"
        ]
      waitForDeploymentReadyReplicasAtLeast state "infernix-engine" 1
      waitForDeploymentReadyReplicasAtLeast state "infernix-coordinator" 1
      context <- createDurablePromptContext paths runtimeMode (Text.pack representativeModelId) "engine-drain"
      waitForDispatcherDiscovery
      promptRef <- submitDurablePrompt paths runtimeMode context "engine-node-drain"
      resultPayload <-
        waitForConversationResultPayloadForPrompt
          paths
          runtimeMode
          (durablePromptConversationTopic context)
          (durablePromptRefMessageId promptRef)
      assertCompletedResultPayload resultPayload "durable prompt completes while an engine node is drained"
      assertPromptPipelineExactlyOnce paths runtimeMode promptRef
    )
    `finally` restore

validateModelBootstrapDeduplication :: Paths -> ClusterState -> RuntimeMode -> IO ()
validateModelBootstrapDeduplication paths state runtimeMode = do
  waitForDeploymentReadyReplicasAtLeast state "infernix-coordinator" 2
  runToken <- Text.pack <$> integrationRunToken
  let modelIdText = "integration-bootstrap-chaos-" <> runToken
      request =
        BootstrapModels.ModelBootstrapRequest
          { BootstrapModels.bootstrapRequestModelId = modelIdText,
            BootstrapModels.bootstrapRequestDownloadUrl = "http://infernix-demo.platform.svc.cluster.local/",
            BootstrapModels.bootstrapRequestRequestedAtIso8601 = "2026-06-02T00:00:00Z"
          }
      readyTopic =
        ConversationTopic.modelBootstrapReadyTopicName ConversationTopic.systemTopicNamespace modelIdText
  publishModelBootstrapRequest paths runtimeMode Nothing request
  oldPod <- requirePodByPrefix state "platform" "infernix-coordinator-"
  runKubectl state ["-n", "platform", "delete", "pod", oldPod]
  publishModelBootstrapRequest paths runtimeMode Nothing request
  publishModelBootstrapRequest paths runtimeMode Nothing request
  waitForRollout state "deployment/infernix-coordinator"
  _ <- waitForPodByPrefix state "platform" "infernix-coordinator-" (Just oldPod)
  readyMessages <- waitForBootstrapReadyMessages paths runtimeMode readyTopic modelIdText
  assert
    (length readyMessages == 1)
    ("model-bootstrap producer dedup yields exactly one ready event, saw " <> show (length readyMessages))

waitForBootstrapReadyMessages :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO [BootstrapModels.ModelBootstrapReadyEvent]
waitForBootstrapReadyMessages paths runtimeMode readyTopic modelIdText = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail ("timed out waiting for model-bootstrap ready event on " <> Text.unpack readyTopic)
      | otherwise = do
          messages <- readRawTopicPayloads paths runtimeMode Nothing readyTopic 16
          let readyEvents =
                [ readyEvent
                | rawMessage <- messages,
                  Right readyEvent <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)],
                  BootstrapModels.readyEventModelId readyEvent == modelIdText
                ]
          if null readyEvents
            then do
              threadDelay 1000000
              go (remainingAttempts - 1)
            else do
              threadDelay 2000000
              settledMessages <- readRawTopicPayloads paths runtimeMode Nothing readyTopic 16
              pure
                [ readyEvent
                | rawMessage <- settledMessages,
                  Right readyEvent <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)],
                  BootstrapModels.readyEventModelId readyEvent == modelIdText
                ]

data ThroughputMatrix = ThroughputMatrix
  { throughputUserCount :: Int,
    throughputContextsPerUser :: Int,
    throughputPromptsPerContext :: Int
  }

defaultThroughputMatrix :: ThroughputMatrix
defaultThroughputMatrix =
  ThroughputMatrix
    { throughputUserCount = 3,
      throughputContextsPerUser = 2,
      throughputPromptsPerContext = 2
    }

validateMultiUserDurablePromptThroughput :: Paths -> RuntimeMode -> String -> IO ()
validateMultiUserDurablePromptThroughput =
  validateMultiUserDurablePromptThroughputWith defaultThroughputMatrix

validateMultiUserDurablePromptThroughputWith :: ThroughputMatrix -> Paths -> RuntimeMode -> String -> IO ()
validateMultiUserDurablePromptThroughputWith matrix paths runtimeMode representativeModelId = do
  let userCount = throughputUserCount matrix
      contextsPerUser = throughputContextsPerUser matrix
      promptsPerContext = throughputPromptsPerContext matrix
      contextLabels =
        [ "throughput-u" <> Text.pack (show userIndex) <> "-c" <> Text.pack (show contextIndex)
        | userIndex <- [1 .. userCount],
          contextIndex <- [1 .. contextsPerUser]
        ]
  contexts <-
    forM contextLabels $
      createDurablePromptContext paths runtimeMode (Text.pack representativeModelId)
  waitForDispatcherDiscovery
  promptRefs <-
    fmap concat $
      forM contexts $ \context ->
        forM [1 .. promptsPerContext] $ \promptIndex ->
          submitDurablePrompt
            paths
            runtimeMode
            context
            ("throughput-p" <> Text.pack (show promptIndex))
  latencies <-
    forM promptRefs $ \promptRef -> do
      resultPayload <-
        waitForConversationResultPayloadForPrompt
          paths
          runtimeMode
          (durablePromptConversationTopic (durablePromptRefContext promptRef))
          (durablePromptRefMessageId promptRef)
      assertCompletedResultPayload resultPayload "throughput prompt writes a completed result"
      finishedAt <- realToFrac <$> getPOSIXTime
      pure (finishedAt - durablePromptRefStartedAt promptRef)
  forM_ contexts $ \context ->
    assertContextPromptAndResultCounts paths runtimeMode context promptsPerContext
  let sortedLatencies = sort latencies
      p95Latency = percentile95 sortedLatencies
      totalPrompts = length promptRefs
  putStrLn
    ( "throughput-metrics users="
        <> show userCount
        <> " contextsPerUser="
        <> show contextsPerUser
        <> " promptsPerContext="
        <> show promptsPerContext
        <> " totalPrompts="
        <> show totalPrompts
        <> " p95Seconds="
        <> show p95Latency
    )

assertContextPromptAndResultCounts :: Paths -> RuntimeMode -> DurablePromptContext -> Int -> IO ()
assertContextPromptAndResultCounts paths runtimeMode context expectedPrompts = do
  messages <- readRawTopicPayloads paths runtimeMode Nothing (durablePromptConversationTopic context) 256
  let promptIds =
        [ rawTopicMessageId rawMessage
        | rawMessage <- messages,
          Right (Contracts.ConversationUserPromptEvent _) <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)]
        ]
      resultPromptIds =
        [ Contracts.unMessageId (Contracts.inferenceResultUserPromptMessageId resultPayload)
        | resultPayload <- conversationResultPayloads messages
        ]
  assert
    (length promptIds == expectedPrompts)
    ("throughput context has exactly " <> show expectedPrompts <> " prompt events")
  assert
    (Set.fromList resultPromptIds == Set.fromList promptIds)
    "throughput context has one result for every prompt and no extra result"
  assert
    (length resultPromptIds == expectedPrompts)
    ("throughput context has exactly " <> show expectedPrompts <> " result events")

percentile95 :: [Double] -> Double
percentile95 [] = 0
percentile95 values =
  let position :: Double
      position = 0.95 * fromIntegral (length values)
      index :: Int
      index = max 0 (ceiling position - 1)
   in values !! min index (length values - 1)

validateCompactedTopicBrokerBehavior :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO ()
validateCompactedTopicBrokerBehavior paths runtimeMode modelIdText tokenText = do
  threshold <- readNamespaceCompactionThreshold paths runtimeMode Nothing "infernix/demo"
  assert (threshold == 100 * 1024 * 1024) "Pulsar admin reports the supported demo namespace compaction threshold"

  let namespace = ConversationTopic.defaultDemoTopicNamespace
      runtimeText = runtimeModeId runtimeMode
      userIdValue = Contracts.UserId ("integration-compacted-user-" <> runtimeText <> "-" <> tokenText)
      contextA = Contracts.ContextId ("compacted-context-a-" <> tokenText)
      contextB = Contracts.ContextId ("compacted-context-b-" <> tokenText)
      contextAText = Contracts.unContextId contextA
      contextBText = Contracts.unContextId contextB
      contextTopic = ConversationTopic.contextsMetadataTopicName namespace userIdValue
      contextAOld = Contracts.ContextCreated contextA modelIdText "old context title"
      contextBEvent = Contracts.ContextCreated contextB modelIdText "stable context title"
      contextALatest = Contracts.ContextRenamed contextA "new context title"
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientCreateContext contextA modelIdText "old context title")
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientCreateContext contextB modelIdText "stable context title")
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientRenameContext contextA "new context title")
  compactTopicAndWait paths runtimeMode Nothing contextTopic
  compactedContextMessages <- waitForJavaCompactedTopicMessages paths contextTopic 2
  assertCompactedTopicMessageKeysExactly
    compactedContextMessages
    (Set.fromList [Just contextAText, Just contextBText])
    "compacted contexts topic yields one latest message per context id"
  assertCompactedTopicHasDecoded compactedContextMessages contextALatest "compacted contexts topic keeps the latest event for context A"
  assertCompactedTopicHasDecoded compactedContextMessages contextBEvent "compacted contexts topic keeps context B's latest event"
  assertCompactedTopicDoesNotHaveDecoded compactedContextMessages contextAOld "compacted contexts topic omits context A's superseded event"

  let draftA = Contracts.ContextId ("compacted-draft-a-" <> tokenText)
      draftB = Contracts.ContextId ("compacted-draft-b-" <> tokenText)
      draftAText = Contracts.unContextId draftA
      draftBText = Contracts.unContextId draftB
      draftsTopic = ConversationTopic.draftsMetadataTopicName namespace userIdValue
      draftAOld = Contracts.DraftUpdated draftA "old draft"
      draftBEvent = Contracts.DraftUpdated draftB "stable draft"
      draftALatest = Contracts.DraftUpdated draftA "new draft"
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientUpdateDraft draftA "old draft")
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientUpdateDraft draftB "stable draft")
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientUpdateDraft draftA "new draft")
  compactTopicAndWait paths runtimeMode Nothing draftsTopic
  compactedDraftMessages <- waitForJavaCompactedTopicMessages paths draftsTopic 2
  assertCompactedTopicMessageKeysExactly
    compactedDraftMessages
    (Set.fromList [Just draftAText, Just draftBText])
    "compacted drafts topic yields one latest message per context id"
  assertCompactedTopicHasDecoded compactedDraftMessages draftALatest "compacted drafts topic keeps the latest draft for context A"
  assertCompactedTopicHasDecoded compactedDraftMessages draftBEvent "compacted drafts topic keeps context B's latest draft"
  assertCompactedTopicDoesNotHaveDecoded compactedDraftMessages draftAOld "compacted drafts topic omits context A's superseded draft"

validateProducerDeduplicationBehavior :: Paths -> RuntimeMode -> Text.Text -> IO ()
validateProducerDeduplicationBehavior paths runtimeMode tokenText = do
  let namespace = ConversationTopic.defaultDemoTopicNamespace
      runtimeText = runtimeModeId runtimeMode
      userIdValue = Contracts.UserId ("integration-dedup-user-" <> runtimeText <> "-" <> tokenText)
      contextIdValue = Contracts.ContextId ("dedup-context-" <> tokenText)
      conversationTopic = ConversationTopic.conversationTopicName namespace userIdValue contextIdValue
      promptMessageId = Contracts.MessageId ("dedup-prompt-" <> runtimeText <> "-" <> tokenText)
      cancelEvent =
        Contracts.ConversationCancelEvent
          (Contracts.ConversationCancelPayload promptMessageId)
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientCancelPrompt contextIdValue promptMessageId)
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientCancelPrompt contextIdValue promptMessageId)
  conversationMessages <- waitForSettledRawTopicMessages paths runtimeMode conversationTopic 2
  assert
    (length conversationMessages == 1)
    "Pulsar producer dedup collapses duplicate append-only conversation publishes with the same frontend sequence id"
  assertTopicHasDecoded conversationMessages cancelEvent "deduplicated conversation publish keeps the original event payload"

  let draftsTopic = ConversationTopic.draftsMetadataTopicName namespace userIdValue
      draftEvent = Contracts.DraftUpdated contextIdValue "dedup draft"
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientUpdateDraft contextIdValue "dedup draft")
  publishDemoClientMessage paths runtimeMode Nothing userIdValue (Contracts.ClientUpdateDraft contextIdValue "dedup draft")
  draftMessages <- waitForSettledRawTopicMessages paths runtimeMode draftsTopic 2
  assert
    (length draftMessages == 1)
    "Pulsar producer dedup collapses duplicate compacted draft publishes with the same frontend sequence id"
  assertTopicHasDecoded draftMessages draftEvent "deduplicated draft publish keeps the original event payload"

validateDurableContextPromptRoundTrip :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO ()
validateDurableContextPromptRoundTrip paths runtimeMode modelIdText tokenText = do
  context <- createDurablePromptContext paths runtimeMode modelIdText ("roundtrip-" <> tokenText)
  waitForDispatcherDiscovery
  promptRef <- submitDurablePrompt paths runtimeMode context "roundtrip"
  resultPayload <-
    waitForConversationResultPayloadForPrompt
      paths
      runtimeMode
      (durablePromptConversationTopic context)
      (durablePromptRefMessageId promptRef)
  assert
    (Contracts.inferenceResultStatus resultPayload == "completed")
    ( "durable context prompt roundtrip writes a completed inference result to the conversation log: "
        <> show resultPayload
    )
  assert
    (isJust (Contracts.inferenceResultInlineOutput resultPayload))
    "durable context prompt roundtrip writes inline output to the conversation log"

conversationResultPayloads :: [RawTopicMessage] -> [Contracts.ConversationInferenceResultPayload]
conversationResultPayloads messages =
  [ resultPayload
  | rawMessage <- messages,
    Right conversationEvent <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)],
    Contracts.ConversationInferenceResultEvent resultPayload <- [conversationEvent]
  ]

waitForRawTopicMessages :: Paths -> RuntimeMode -> Text.Text -> Int -> IO [RawTopicMessage]
waitForRawTopicMessages paths runtimeMode topic expectedCount = go (6 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = fail ("timed out waiting for Pulsar topic " <> Text.unpack topic)
      | otherwise = do
          messages <- readRawTopicPayloads paths runtimeMode Nothing topic expectedCount
          if length messages >= expectedCount
            then pure messages
            else do
              threadDelay 500000
              go (remainingAttempts - 1)

waitForSettledRawTopicMessages :: Paths -> RuntimeMode -> Text.Text -> Int -> IO [RawTopicMessage]
waitForSettledRawTopicMessages paths runtimeMode topic maxMessages = do
  _ <- waitForRawTopicMessages paths runtimeMode topic 1
  threadDelay 1000000
  readRawTopicPayloads paths runtimeMode Nothing topic maxMessages

waitForJavaCompactedTopicMessages :: Paths -> Text.Text -> Int -> IO [CompactedTopicMessage]
waitForJavaCompactedTopicMessages paths topic expectedCount = go (10 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = fail ("timed out waiting for compacted Pulsar topic " <> Text.unpack topic)
      | otherwise = do
          messages <- readCompactedTopicMessagesWithJavaReader paths topic expectedCount
          if length messages >= expectedCount
            then pure messages
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)

assertTopicMessageKey :: [RawTopicMessage] -> Maybe Text.Text -> String -> IO ()
assertTopicMessageKey messages expectedKey =
  assert (any ((== expectedKey) . rawTopicMessageKey) messages)

assertCompactedTopicMessageKeysExactly :: [CompactedTopicMessage] -> Set.Set (Maybe Text.Text) -> String -> IO ()
assertCompactedTopicMessageKeysExactly messages expectedKeys =
  assert (Set.fromList (map compactedTopicMessageKey messages) == expectedKeys)

assertTopicHasDecoded :: (Aeson.FromJSON a, Eq a) => [RawTopicMessage] -> a -> String -> IO ()
assertTopicHasDecoded messages expectedValue =
  assert (expectedValue `elem` decodedValues)
  where
    decodedValues =
      [ decoded
      | rawMessage <- messages,
        Right decoded <- [Aeson.eitherDecodeStrict' (rawTopicMessagePayload rawMessage)]
      ]

assertCompactedTopicHasDecoded :: (Aeson.FromJSON a, Eq a) => [CompactedTopicMessage] -> a -> String -> IO ()
assertCompactedTopicHasDecoded messages expectedValue =
  assert (expectedValue `elem` decodedValues)
  where
    decodedValues =
      [ decoded
      | rawMessage <- messages,
        Right decoded <- [Aeson.eitherDecodeStrict' (compactedTopicMessagePayload rawMessage)]
      ]

assertCompactedTopicDoesNotHaveDecoded :: (Aeson.FromJSON a, Eq a) => [CompactedTopicMessage] -> a -> String -> IO ()
assertCompactedTopicDoesNotHaveDecoded messages unexpectedValue =
  assert (unexpectedValue `notElem` decodedValues)
  where
    decodedValues =
      [ decoded
      | rawMessage <- messages,
        Right decoded <- [Aeson.eitherDecodeStrict' (compactedTopicMessagePayload rawMessage)]
      ]

readCompactedTopicMessagesWithJavaReader :: Paths -> Text.Text -> Int -> IO [CompactedTopicMessage]
readCompactedTopicMessagesWithJavaReader paths topic expectedCount = do
  output <-
    readProcess
      "kubectl"
      [ "--kubeconfig",
        Config.generatedKubeconfigPath paths,
        "-n",
        "platform",
        "exec",
        "infernix-infernix-pulsar-toolset-0",
        "--",
        "bash",
        "-lc",
        compactedReaderScript topic expectedCount
      ]
      ""
  traverse parseCompactedReaderLine (filter (elem '\t') (lines output))

compactedReaderScript :: Text.Text -> Int -> String
compactedReaderScript topic expectedCount =
  unlines
    [ "cat >/tmp/InfernixReadCompacted.java <<'JAVA'",
      "import java.nio.charset.StandardCharsets;",
      "import java.util.concurrent.TimeUnit;",
      "import org.apache.pulsar.client.api.Message;",
      "import org.apache.pulsar.client.api.MessageId;",
      "import org.apache.pulsar.client.api.PulsarClient;",
      "import org.apache.pulsar.client.api.Reader;",
      "public class InfernixReadCompacted {",
      "  public static void main(String[] args) throws Exception {",
      "    try (PulsarClient client = PulsarClient.builder().serviceUrl(args[0]).build();",
      "         Reader<byte[]> reader = client.newReader().topic(args[1]).startMessageId(MessageId.earliest).readCompacted(true).create()) {",
      "      int expected = Integer.parseInt(args[2]);",
      "      for (int i = 0; i < expected; i++) {",
      "        Message<byte[]> message = reader.readNext(5, TimeUnit.SECONDS);",
      "        if (message == null) { break; }",
      "        String key = message.getKey() == null ? \"\" : message.getKey();",
      "        System.out.println(key + \"\\t\" + new String(message.getData(), StandardCharsets.UTF_8));",
      "      }",
      "    }",
      "  }",
      "}",
      "JAVA",
      "/opt/jvm/bin/javac -cp '/pulsar/lib/*' /tmp/InfernixReadCompacted.java",
      "/opt/jvm/bin/java -cp '/tmp:/pulsar/lib/*' InfernixReadCompacted "
        <> shellSingleQuote "pulsar://infernix-infernix-pulsar-proxy:6650"
        <> " "
        <> shellSingleQuote (Text.unpack topic)
        <> " "
        <> shellSingleQuote (show expectedCount)
    ]

parseCompactedReaderLine :: String -> IO CompactedTopicMessage
parseCompactedReaderLine raw =
  case break (== '\t') raw of
    (rawKey, '\t' : payload) ->
      pure
        CompactedTopicMessage
          { compactedTopicMessageKey = if null rawKey then Nothing else Just (Text.pack rawKey),
            compactedTopicMessagePayload = ByteString8.pack payload
          }
    _ -> fail ("unexpected compacted-reader output line: " <> raw)

shellSingleQuote :: String -> String
shellSingleQuote value =
  "'" <> concatMap quoteChar value <> "'"
  where
    quoteChar '\'' = "'\\''"
    quoteChar ch = [ch]

-- | Phase 6 Sprint 6.28 follow-on (May 26, 2026): bumped the
-- per-request inference roundtrip timeout from 6 s (60 attempts at
-- 100 ms) to 5 minutes (3000 attempts at 100 ms). The supported
-- cluster lifecycle's first-run inference includes Poetry adapter
-- bootstrap (~30 s) plus Pulsar coordinator/engine two-hop
-- handoff; the previous 6 s ceiling was sufficient only for warm
-- in-process unit-style runs and was unrealistic for the
-- routed-cluster integration path.
waitForPublishedResult :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
waitForPublishedResult paths runtimeMode resultTopic requestIdValue = go (3000 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure Nothing
      | otherwise = do
          maybeResult <- readPublishedInferenceResultMaybe paths runtimeMode resultTopic requestIdValue
          case maybeResult of
            Just resultValue -> pure (Just resultValue)
            Nothing -> do
              threadDelay 100000
              go (remainingAttempts - 1)

validateEdgePortConflictAndRediscovery :: Paths -> RuntimeMode -> IO ()
validateEdgePortConflictAndRediscovery paths runtimeMode = do
  cleanupRuntimeState paths
  busyState <-
    bracket (openBusyTcpPort 9090) close $ \_busySocket -> do
      waitForPortConflictHelper
      withClusterLifecycle runtimeMode $ do
        maybeState <- loadClusterState paths
        state <- maybe (fail "cluster state was not available after busy-port cluster up") pure maybeState
        assert (edgePort state > 9090) "cluster up chooses a non-9090 port when 9090 is busy"
        pure state
  withClusterLifecycle runtimeMode $ do
    maybeRediscoveredState <- loadClusterState paths
    assert (maybe False ((== edgePort busyState) . edgePort) maybeRediscoveredState) "cluster up reuses the published edge port after restart"
  where
    waitForPortConflictHelper = do
      threadDelay 250000

openBusyTcpPort :: Int -> IO Socket
openBusyTcpPort port = do
  busySocket <- socket AF_INET Stream defaultProtocol
  setSocketOption busySocket ReuseAddr 1
  bind busySocket (SockAddrInet (fromIntegral port) (tupleToHostAddress (127, 0, 0, 1)))
  listen busySocket 1
  pure busySocket

validateDemoUiDisabled :: Paths -> RuntimeMode -> IO ()
validateDemoUiDisabled paths runtimeMode =
  ( do
      cleanupRuntimeState paths
      materializeGeneratedSubstrate runtimeMode False
      withClusterLifecycle runtimeMode $ do
        state <- maybe (fail "cluster state was not available after demo-disabled cluster up") pure =<< loadClusterState paths
        assert (clusterPresent state) "cluster up records cluster presence when demo_ui is disabled"
        assert (not (any ((== "/") . path) (routes state))) "route inventory omits the browser root when demo_ui is disabled"
        assert (not (any ((== "/api") . path) (routes state))) "route inventory omits the demo API when demo_ui is disabled"
        let baseUrl = routeBaseUrl paths state
        disabledHomeResult <- try (httpGet (baseUrl <> "/")) :: IO (Either IOError String)
        disabledPublicationResult <- try (httpGet (baseUrl <> "/api/publication")) :: IO (Either IOError String)
        harborResponse <- httpGet (baseUrl <> "/harbor")
        pulsarAdminResponse <- httpGet (baseUrl <> "/pulsar/admin/admin/v2/clusters")
        (minioS3Status, minioS3Response) <- httpGetWithStatus (baseUrl <> "/minio/s3/models/demo.bin")
        (pulsarHttpStatus, _) <- httpGetWithStatus (baseUrl <> "/pulsar/ws/v2/producer/public/default/demo")
        assert (either (const True) (const False) disabledHomeResult) "the browser root is absent when demo_ui is disabled"
        assert (either (const True) (const False) disabledPublicationResult) "the demo API is absent when demo_ui is disabled"
        assert ("Harbor" `isInfixOf` harborResponse) "harbor remains published when demo_ui is disabled"
        assert
          (minioS3Status `elem` [200, 401, 403, 404] && "\"rewrittenPath\"" `notElemString` compact minioS3Response)
          "minio remains published when demo_ui is disabled"
        assert
          ("[\"infernix-infernix-pulsar\"]" `isInfixOf` compact pulsarAdminResponse)
          "pulsar admin remains published when demo_ui is disabled"
        assert
          (pulsarHttpStatus == 405)
          "pulsar websocket route remains published when demo_ui is disabled"
  )
    `finally` materializeGeneratedSubstrate runtimeMode True

resolveInfernixExecutable :: IO FilePath
resolveInfernixExecutable =
  trimTrailingWhitespace <$> readProcess "cabal" ["list-bin", "exe:infernix"] ""

trimTrailingWhitespace :: String -> String
trimTrailingWhitespace =
  reverse . dropWhile (`elem` [' ', '\n', '\r', '\t']) . reverse

trim :: String -> String
trim =
  dropWhile (`elem` [' ', '\n', '\r', '\t'])
    . reverse
    . dropWhile (`elem` [' ', '\n', '\r', '\t'])
    . reverse

cleanupRuntimeState :: Paths -> IO ()
cleanupRuntimeState paths = do
  catchIOError (removePathForcibly (runtimeRoot paths)) ignoreMissing
  createDirectoryIfMissing True (runtimeRoot paths)
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

captureInfernixOutput :: [String] -> IO String
captureInfernixOutput args = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readProcessWithExitCode
      "cabal"
      ( [ "run",
          "exe:infernix",
          "--"
        ]
          <> args
      )
      ""
  assert (exitCode == ExitSuccess) ("infernix command succeeded: " <> stderrOutput)
  pure stdoutOutput

httpGet :: String -> IO String
httpGet url =
  readProcessWithTransientCurlRetry ["-fsS", url]

httpGetWithStatus :: String -> IO (Int, String)
httpGetWithStatus url = do
  payload <-
    readProcessWithTransientCurlRetry
      ["-sS", "-o", "-", "-w", "\n%{http_code}", url]
  case parseCurlBodyAndStatus payload of
    Just (body, statusCodeValue) -> pure (statusCodeValue, body)
    Nothing -> fail ("failed to parse curl status output for " <> url)

readProcessWithTransientCurlRetry :: [String] -> IO String
readProcessWithTransientCurlRetry args = go (20 :: Int)
  where
    go attemptsRemaining =
      catchIOError
        (readProcess "curl" args "")
        ( \err ->
            if attemptsRemaining > 1 && isTransientCurlConnectionError err
              then do
                threadDelay 500000
                go (attemptsRemaining - 1)
              else ioError err
        )

isTransientCurlConnectionError :: IOError -> Bool
isTransientCurlConnectionError err =
  let message = show err
   in "Connection refused" `isInfixOf` message
        || "Failed to connect" `isInfixOf` message
        || "Connection reset by peer" `isInfixOf` message
        || "Empty reply from server" `isInfixOf` message

parseCurlBodyAndStatus :: String -> Maybe (String, Int)
parseCurlBodyAndStatus payload =
  case reverse (lines payload) of
    rawStatus : remainingLines ->
      case reads rawStatus of
        [(statusCodeValue, "")] ->
          Just (unlines (reverse remainingLines), statusCodeValue)
        _ -> Nothing
    [] -> Nothing

requireJsonDemoConfig :: String -> IO DemoConfig
requireJsonDemoConfig payload =
  case Aeson.decode (LazyByteStringChar8.pack payload) of
    Just demoConfig -> pure demoConfig
    Nothing -> fail "unable to decode routed demo config JSON"

compact :: String -> String
compact = filter (`notElem` [' ', '\n', '\r', '\t'])

notElemString :: String -> String -> Bool
notElemString needle haystack = not (needle `isInfixOf` haystack)

routeBaseUrl :: Paths -> ClusterState -> String
routeBaseUrl paths state =
  let (hostName, portNumber) = routeProbeHostAndPort paths state
   in "http://" <> hostName <> ":" <> show portNumber

routeProbeHostAndPort :: Paths -> ClusterState -> (String, Int)
routeProbeHostAndPort paths state
  | Config.controlPlaneContext paths == Config.OuterContainer =
      (kindControlPlaneNodeName paths (clusterRuntimeMode state), 30090)
  | otherwise = ("127.0.0.1", edgePort state)

mapToLowerAscii :: String -> String
mapToLowerAscii = map toLowerAscii

toLowerAscii :: Char -> Char
toLowerAscii char
  | isAsciiUpper char = toEnum (fromEnum char + 32)
  | otherwise = char

showRuntimeMode :: RuntimeMode -> String
showRuntimeMode = Text.unpack . runtimeModeId

withTestRoot :: FilePath -> IO a -> IO a
withTestRoot root action = do
  catchIOError (removePathForcibly root) ignoreMissing
  createDirectoryIfMissing True root
  withCurrentDirectory root action
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

testRootPath :: FilePath -> IO FilePath
testRootPath suiteName = do
  paths <- Config.discoverPaths
  pure (repoRoot paths </> ".build" </> ("test-" <> suiteName))

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message

materializeGeneratedSubstrate :: RuntimeMode -> Bool -> IO ()
materializeGeneratedSubstrate runtimeMode demoUiEnabledValue = do
  let demoUiFlag =
        if demoUiEnabledValue
          then "true"
          else "false"
  _ <-
    captureInfernixOutput
      [ "internal",
        "materialize-substrate",
        showRuntimeMode runtimeMode,
        "--demo-ui",
        demoUiFlag
      ]
  pure ()

reportStep :: String -> IO ()
reportStep message = do
  putStrLn ("integration-step: " <> message)
  hFlush stdout

validateHarborRecovery :: ClusterState -> IO ()
validateHarborRecovery state = do
  harborCorePod <- requirePodByPrefix state "platform" "infernix-harbor-core-"
  runKubectl state ["-n", "platform", "delete", "pod", harborCorePod]
  waitForRollout state "deployment/infernix-harbor-core"
  _ <- waitForPodByPrefix state "platform" "infernix-harbor-core-" (Just harborCorePod)
  validateHarborBackedImagePull state

validateHarborBackedImagePull :: ClusterState -> IO ()
validateHarborBackedImagePull state = do
  serviceImage <-
    trim
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "deployment",
          "infernix-coordinator",
          "-o",
          "jsonpath={.spec.template.spec.containers[0].image}"
        ]
  let podName = "harbor-pull-smoke"
  runKubectlWithInput
    state
    ["-n", "platform", "apply", "-f", "-"]
    ( unlines
        [ "apiVersion: v1",
          "kind: Pod",
          "metadata:",
          "  name: " <> podName,
          "  namespace: platform",
          "spec:",
          "  restartPolicy: Never",
          "  containers:",
          "    - name: pull-smoke",
          "      image: " <> serviceImage,
          "      imagePullPolicy: Always",
          "      command: [\"sh\", \"-lc\", \"sleep 20\"]"
        ]
    )
  waitForPodReady state "platform" podName
  runKubectl state ["-n", "platform", "delete", "pod", podName, "--ignore-not-found=true"]

validateMinioDurability :: ClusterState -> IO ()
validateMinioDurability state = do
  (minioPod, mountPath) <- requirePodWithMountByPrefix state "platform" "infernix-minio" "data"
  assert (not (null mountPath)) "minio data volume mount path is discoverable"
  let sentinelPath = mountPath <> "/ha-smoke/minio-sentinel.txt"
  runKubectl state ["-n", "platform", "exec", minioPod, "--", "sh", "-lc", "mkdir -p " <> mountPath <> "/ha-smoke && printf minio-durable > " <> sentinelPath]
  runKubectl state ["-n", "platform", "delete", "pod", minioPod]
  waitForPodReady state "platform" minioPod
  sentinelContents <- trim <$> kubectlOutputForState state ["-n", "platform", "exec", minioPod, "--", "sh", "-lc", "cat " <> sentinelPath]
  assert (sentinelContents == "minio-durable") "minio data written before pod replacement remains available afterward"

validateRoutedPulsarRecovery :: Paths -> ClusterState -> RuntimeMode -> [String] -> IO ()
validateRoutedPulsarRecovery paths state runtimeMode activeModelIds =
  case activeModelIds of
    firstModelId : secondModelId : _ -> do
      publishAndRequireResultWithRetry paths runtimeMode firstModelId "pulsar-pre-restart"
      runKubectl state ["-n", "platform", "delete", "pod", "infernix-infernix-pulsar-broker-0"]
      waitForPodReady state "platform" "infernix-infernix-pulsar-broker-0"
      publishAndRequireResultWithRetry paths runtimeMode secondModelId "pulsar-post-restart"
    _ -> fail "need at least two catalog entries to validate routed Pulsar recovery"

publishAndRequireResult :: Paths -> RuntimeMode -> String -> String -> IO ()
publishAndRequireResult paths runtimeMode modelIdValue inputValue = do
  requestTopic <-
    case requestTopicsForMode runtimeMode of
      topic : _ -> pure topic
      [] -> fail ("no request topic configured for " <> showRuntimeMode runtimeMode)
  let resultTopic = resultTopicForMode runtimeMode
  requestIdValue <-
    publishInferenceRequest
      paths
      runtimeMode
      requestTopic
      InferenceRequest
        { requestModelId = Text.pack modelIdValue,
          inputText = Text.pack inputValue
        }
  maybeResult <- waitForPublishedResult paths runtimeMode resultTopic requestIdValue
  case maybeResult of
    Nothing -> fail ("pulsar roundtrip did not publish a result for " <> modelIdValue)
    Just resultValue ->
      assert (resultModelId resultValue == Text.pack modelIdValue) ("pulsar roundtrip preserves the selected model id for " <> modelIdValue)

withRuntimeServiceDaemonIfNeeded :: Paths -> RuntimeMode -> IO a -> IO a
withRuntimeServiceDaemonIfNeeded paths runtimeMode action
  | requiresHostServiceHarness paths runtimeMode =
      let readinessMarker = serviceReadinessMarkerPath paths
          logPath = hostServiceDaemonLogPath paths
       in do
            catchIOError (removeFile readinessMarker) ignoreMissing
            withRuntimeServiceDaemon paths $ do
              waitForFileWithLog readinessMarker logPath hostServiceDaemonReadinessAttempts
              action
  | otherwise = action
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

-- | The host engine daemon discovers the Apple-substrate Pulsar
-- transport from the published edge port, reconciles supported
-- namespaces, and registers schemas before it writes the readiness
-- marker. The supported envelope is 5 minutes; failures surface the
-- daemon log so the operator does not have to guess.
hostServiceDaemonReadinessAttempts :: Int
hostServiceDaemonReadinessAttempts = 3000

waitForFileWithLog :: FilePath -> FilePath -> Int -> IO ()
waitForFileWithLog filePath logPath = go
  where
    go remainingAttempts
      | remainingAttempts <= 0 = do
          logSnapshot <- readDaemonLogSnapshot logPath
          fail
            ( "timed out waiting for "
                <> filePath
                <> "\n--- host service daemon log ("
                <> logPath
                <> ") ---\n"
                <> logSnapshot
            )
      | otherwise = do
          exists <- doesFileExist filePath
          if exists
            then pure ()
            else do
              threadDelay 100000
              go (remainingAttempts - 1)

readDaemonLogSnapshot :: FilePath -> IO String
readDaemonLogSnapshot logPath = do
  present <- doesFileExist logPath
  if not present
    then pure "(no host service daemon log was produced)\n"
    else readFile logPath

requiresHostServiceHarness :: Paths -> RuntimeMode -> Bool
requiresHostServiceHarness paths runtimeMode =
  Config.controlPlaneContext paths /= Config.OuterContainer && runtimeMode == AppleSilicon

-- | Phase 7 Sprint 7.14 (2026-05-31): Linux engine pod anti-affinity chaos case.
-- The chart's `infernix-engine` Deployment carries
-- `requiredDuringSchedulingIgnoredDuringExecution` anti-affinity keyed by
-- hostname (`topologyKey: kubernetes.io/hostname`), so scaling the deployment
-- past the available engine-capable node count must leave the extra replica
-- `Pending` with a scheduler `FailedScheduling` event naming pod anti-affinity.
-- The supported recovery is to scale back to the original replica count and
-- wait for the deployment to roll back to ready.
validateLinuxEngineAntiAffinityEnforcement :: ClusterState -> IO ()
validateLinuxEngineAntiAffinityEnforcement state = do
  runKubectl state ["-n", "platform", "rollout", "status", "deployment/infernix-engine", "--timeout=900s"]
  originalReplicas <- deploymentSpecReplicas state "infernix-engine"
  let surplusReplicas = originalReplicas + 1
      restore =
        runKubectl state ["-n", "platform", "scale", "deployment/infernix-engine", "--replicas=" <> show originalReplicas]
          >> runKubectl state ["-n", "platform", "rollout", "status", "deployment/infernix-engine", "--timeout=900s"]
  ( do
      runKubectl state ["-n", "platform", "scale", "deployment/infernix-engine", "--replicas=" <> show surplusReplicas]
      pendingPod <- waitForPendingEnginePod state
      events <-
        kubectlOutputForState
          state
          [ "-n",
            "platform",
            "get",
            "events",
            "--field-selector",
            "involvedObject.name=" <> pendingPod,
            "-o",
            "jsonpath={range .items[*]}{.reason}|{.message}{\"\\n\"}{end}"
          ]
      assert
        ("FailedScheduling" `isInfixOf` events)
        "the surplus engine pod surfaces a FailedScheduling scheduler event under anti-affinity"
      assert
        ("anti-affinity" `isInfixOf` events || "AntiAffinity" `isInfixOf` events)
        "the FailedScheduling event names pod anti-affinity as the reason"
    )
    `finally` restore

waitForPendingEnginePod :: ClusterState -> IO String
waitForPendingEnginePod state = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail "timed out waiting for a Pending infernix-engine pod after scaling the deployment past available engine nodes"
      | otherwise = do
          podLines <-
            lines
              <$> kubectlOutputForState
                state
                [ "-n",
                  "platform",
                  "get",
                  "pods",
                  "-l",
                  "app.kubernetes.io/name=infernix-engine",
                  "-o",
                  "jsonpath={range .items[*]}{.metadata.name}|{.status.phase}{\"\\n\"}{end}"
                ]
          case find (\line -> "|Pending" `isInfixOf` line) podLines of
            Just match -> pure (takeWhile (/= '|') match)
            Nothing -> do
              threadDelay 1000000
              go (remainingAttempts - 1)

-- | Phase 7 Sprint 7.14 (2026-05-31): Apple engine.lock enforcement chaos case.
-- Spawn a second @infernix service@ while the harness-owned first daemon is
-- alive. The second invocation must exit non-zero because
-- `Infernix.Service.acquireEngineLock` cannot acquire the flock; the stderr
-- must surface the supported diagnostic naming the holding PID so operators
-- can find the existing daemon.
validateAppleEngineLockEnforcement :: Paths -> IO ()
validateAppleEngineLockEnforcement paths = do
  infernixExecutable <- resolveInfernixExecutable
  (exitCode, _stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc infernixExecutable ["service"]) {cwd = Just (repoRoot paths)}
      ""
  assert
    (exitCode /= ExitSuccess)
    "a second `infernix service` invocation exits non-zero when the engine.lock is already held"
  assert
    ("engine.lock" `isInfixOf` stderrOutput)
    "the second `infernix service` invocation surfaces the engine.lock diagnostic on stderr"
  assert
    ("is held by PID" `isInfixOf` stderrOutput)
    "the engine.lock diagnostic names the holder PID for operator triage"

withRuntimeServiceDaemon :: Paths -> IO a -> IO a
withRuntimeServiceDaemon paths action = do
  infernixExecutable <- resolveInfernixExecutable
  let logPath = hostServiceDaemonLogPath paths
  createDirectoryIfMissing True (takeDirectoryPortable logPath)
  logHandle <- openFile logPath WriteMode
  hSetBuffering logHandle LineBuffering
  reportStep ("apple host service daemon log: " <> logPath)
  (_, _, _, processHandle) <-
    createProcess
      (proc infernixExecutable ["service"])
        { cwd = Just (repoRoot paths),
          std_out = UseHandle logHandle,
          std_err = UseHandle logHandle
        }
  action
    `finally` do
      terminateProcess processHandle
      _ <- waitForProcess processHandle
      hClose logHandle

hostServiceDaemonLogPath :: Paths -> FilePath
hostServiceDaemonLogPath paths =
  runtimeRoot paths </> "service" </> "host-service-daemon.log"

takeDirectoryPortable :: FilePath -> FilePath
takeDirectoryPortable filePath =
  case reverse (dropWhile (/= '/') (reverse filePath)) of
    "" -> "."
    parentWithSlash -> reverse (dropWhile (== '/') (reverse parentWithSlash))

expectedInferenceDispatchMode :: RuntimeMode -> String
expectedInferenceDispatchMode runtimeMode =
  case runtimeMode of
    AppleSilicon -> "pulsar-bridge-to-host-daemon"
    _ -> "pulsar-bridge-to-cluster-daemon"

publishAndRequireResultWithRetry :: Paths -> RuntimeMode -> String -> String -> IO ()
publishAndRequireResultWithRetry paths runtimeMode modelIdValue inputValue = go (24 :: Int) Nothing
  where
    go remainingAttempts maybeLastError = do
      result <- try (publishAndRequireResult paths runtimeMode modelIdValue inputValue) :: IO (Either SomeException ())
      case result of
        Right _ -> pure ()
        Left err
          | remainingAttempts <= 1 ->
              fail
                ( "pulsar roundtrip never recovered for "
                    <> modelIdValue
                    <> maybe "" (" after transient failures: " <>) maybeLastError
                )
          | otherwise -> do
              threadDelay 5000000
              go (remainingAttempts - 1) (Just (displayException err))

validatePostgresFailover :: ClusterState -> IO ()
validatePostgresFailover state = do
  runKubectl state ["-n", "platform", "rollout", "status", "deployment/infernix-postgres-operator", "--timeout=900s"]
  runKubectl state ["-n", "platform", "rollout", "status", "deployment/harbor-postgresql-pgbouncer", "--timeout=900s"]
  primaryBefore <- harborPostgresPrimaryPod state
  bindingsBefore <- postgresPvcBindings state
  assert (not (Map.null bindingsBefore)) "operator-managed PostgreSQL PVC bindings are present before failover"
  runKubectl state ["-n", "platform", "delete", "pod", primaryBefore]
  primaryAfter <- waitForDifferentHarborPrimaryPod state primaryBefore
  assert (primaryAfter /= primaryBefore) "Patroni failover elects a replacement primary pod"

validatePostgresLifecycleRebinding :: Paths -> RuntimeMode -> ClusterState -> IO ()
validatePostgresLifecycleRebinding paths runtimeMode state = do
  inventoryBefore <- postgresPersistentVolumeInventory state
  assert (not (Map.null inventoryBefore)) "operator-managed PostgreSQL persistent-volume inventory is present before cluster lifecycle rebind validation"
  boundVolumesBefore <- postgresBoundVolumeNames state
  assert (boundVolumesBefore == Map.keysSet inventoryBefore) "operator-managed PostgreSQL PVCs bind to the full deterministic Harbor PV inventory before cluster lifecycle rebind validation"
  clusterDown (Just runtimeMode)
  clusterUp (Just runtimeMode)
  reboundState <- maybe (fail "cluster state was not available after lifecycle rebind validation") pure =<< loadClusterState paths
  waitForRollout reboundState "deployment/harbor-postgresql-pgbouncer"
  inventoryAfter <- postgresPersistentVolumeInventory reboundState
  assert (inventoryAfter == inventoryBefore) "operator-managed PostgreSQL lifecycle reuses the same deterministic Harbor PV inventory and host paths after cluster down and cluster up"
  boundVolumesAfter <- postgresBoundVolumeNames reboundState
  assert (boundVolumesAfter == Map.keysSet inventoryAfter) "operator-managed PostgreSQL PVCs rebind onto the deterministic Harbor PV inventory after cluster down and cluster up"

postgresPvcBindings :: ClusterState -> IO (Map.Map String String)
postgresPvcBindings state = do
  bindingLines <-
    lines
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "pvc",
          "-l",
          "postgres-operator.crunchydata.com/cluster=harbor-postgresql",
          "-o",
          "jsonpath={range .items[*]}{.metadata.name}{\"\\t\"}{.spec.volumeName}{\"\\n\"}{end}"
        ]
  pure
    ( Map.fromList
        [ binding
        | lineValue <- bindingLines,
          Just binding <- [parsePvcBinding lineValue]
        ]
    )

postgresBoundVolumeNames :: ClusterState -> IO (Set.Set String)
postgresBoundVolumeNames state =
  Set.fromList . Map.elems <$> postgresPvcBindings state

postgresPersistentVolumeInventory :: ClusterState -> IO (Map.Map String String)
postgresPersistentVolumeInventory state = do
  inventoryLines <-
    lines
      <$> kubectlOutputForState
        state
        [ "get",
          "pv",
          "-o",
          "jsonpath={range .items[*]}{.metadata.name}{\"\\t\"}{.spec.hostPath.path}{\"\\n\"}{end}"
        ]
  pure
    ( Map.fromList
        [ inventoryEntry
        | lineValue <- inventoryLines,
          Just inventoryEntry <- [parsePersistentVolumeInventory lineValue]
        ]
    )

parsePvcBinding :: String -> Maybe (String, String)
parsePvcBinding lineValue =
  case splitTabs lineValue of
    [pvcName, pvName]
      | not (null pvcName) && not (null pvName) -> Just (pvcName, pvName)
    _ -> Nothing

parsePersistentVolumeInventory :: String -> Maybe (String, String)
parsePersistentVolumeInventory lineValue =
  case splitTabs lineValue of
    [pvName, hostPath]
      | harborPostgresPersistentVolumePrefix `isPrefixOf` pvName && not (null hostPath) ->
          Just (pvName, hostPath)
    _ -> Nothing

harborPostgresPersistentVolumePrefix :: String
harborPostgresPersistentVolumePrefix = "platform-infernix-harbor-postgresql-"

harborPostgresPrimaryPod :: ClusterState -> IO String
harborPostgresPrimaryPod state =
  trim
    <$> kubectlOutputForState
      state
      [ "-n",
        "platform",
        "get",
        "pods",
        "-l",
        "postgres-operator.crunchydata.com/cluster=harbor-postgresql,postgres-operator.crunchydata.com/role=primary",
        "--no-headers",
        "-o",
        "custom-columns=:metadata.name"
      ]

waitForDifferentHarborPrimaryPod :: ClusterState -> String -> IO String
waitForDifferentHarborPrimaryPod state previousPrimary = go (72 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = fail "Harbor PostgreSQL primary pod never changed after deleting the previous primary"
      | otherwise = do
          currentPrimary <- harborPostgresPrimaryPod state
          if null currentPrimary || currentPrimary == previousPrimary
            then do
              threadDelay 5000000
              go (remainingAttempts - 1)
            else do
              waitForPodReady state "platform" currentPrimary
              pure currentPrimary

kubectlOutputForState :: ClusterState -> [String] -> IO String
kubectlOutputForState state args = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readProcessWithExitCode
      "kubectl"
      (["--kubeconfig", kubeconfigPath state] <> args)
      ""
  assert (exitCode == ExitSuccess) ("kubectl command succeeded: " <> stderrOutput)
  pure stdoutOutput

runKubectl :: ClusterState -> [String] -> IO ()
runKubectl state args = do
  (exitCode, _, stderrOutput) <-
    readProcessWithExitCode
      "kubectl"
      (["--kubeconfig", kubeconfigPath state] <> args)
      ""
  assert (exitCode == ExitSuccess) ("kubectl command succeeded: " <> stderrOutput)

runKubectlWithInput :: ClusterState -> [String] -> String -> IO ()
runKubectlWithInput state args inputPayload = do
  (exitCode, _, stderrOutput) <-
    readProcessWithExitCode
      "kubectl"
      (["--kubeconfig", kubeconfigPath state] <> args)
      inputPayload
  assert (exitCode == ExitSuccess) ("kubectl command succeeded: " <> stderrOutput)

waitForRollout :: ClusterState -> String -> IO ()
waitForRollout state workload =
  runKubectl state ["-n", "platform", "rollout", "status", workload, "--timeout=900s"]

deploymentSpecReplicas :: ClusterState -> String -> IO Int
deploymentSpecReplicas state deploymentName =
  parseNonNegativeInt ("deployment/" <> deploymentName <> " spec.replicas")
    . trim
    <$> kubectlOutputForState
      state
      [ "-n",
        "platform",
        "get",
        "deployment",
        deploymentName,
        "-o",
        "jsonpath={.spec.replicas}"
      ]

waitForDeploymentReadyReplicasAtLeast :: ClusterState -> String -> Int -> IO ()
waitForDeploymentReadyReplicasAtLeast state deploymentName expectedReplicas = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail ("timed out waiting for deployment/" <> deploymentName <> " ready replicas >= " <> show expectedReplicas)
      | otherwise = do
          readyReplicas <- deploymentReadyReplicas state deploymentName
          if readyReplicas >= expectedReplicas
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)

deploymentReadyReplicas :: ClusterState -> String -> IO Int
deploymentReadyReplicas state deploymentName =
  parseOptionalNonNegativeInt ("deployment/" <> deploymentName <> " status.readyReplicas")
    . trim
    <$> kubectlOutputForState
      state
      [ "-n",
        "platform",
        "get",
        "deployment",
        deploymentName,
        "-o",
        "jsonpath={.status.readyReplicas}"
      ]

parseOptionalNonNegativeInt :: String -> String -> Int
parseOptionalNonNegativeInt _ "" = 0
parseOptionalNonNegativeInt label value = parseNonNegativeInt label value

parseNonNegativeInt :: String -> String -> Int
parseNonNegativeInt label value =
  case reads value of
    [(parsed, "")] | parsed >= (0 :: Int) -> parsed
    _ -> error ("unable to parse " <> label <> " as a non-negative integer: " <> value)

requirePodWithMountByPrefix :: ClusterState -> String -> String -> String -> IO (String, String)
requirePodWithMountByPrefix state namespaceName prefixValue mountName = do
  maybePod <- findPodWithMountByPrefix state namespaceName prefixValue mountName
  case maybePod of
    Just podDetails -> pure podDetails
    Nothing -> fail ("did not find pod with prefix " <> prefixValue <> " and mount " <> mountName)

findPodWithMountByPrefix :: ClusterState -> String -> String -> String -> IO (Maybe (String, String))
findPodWithMountByPrefix state namespaceName prefixValue mountName = do
  podNames <-
    filter (isPrefixOf prefixValue) . filter (not . null) . map trim . lines
      <$> kubectlOutputForState
        state
        ["-n", namespaceName, "get", "pods", "--no-headers", "-o", "custom-columns=:metadata.name"]
  go podNames
  where
    go [] = pure Nothing
    go (podName : remainingPods) = do
      mountPath <- podMountPathForVolume state namespaceName podName mountName
      if null mountPath
        then go remainingPods
        else pure (Just (podName, mountPath))

podMountPathForVolume :: ClusterState -> String -> String -> String -> IO String
podMountPathForVolume state namespaceName podName mountName =
  trim
    <$> kubectlOutputForState
      state
      [ "-n",
        namespaceName,
        "get",
        "pod",
        podName,
        "-o",
        "jsonpath={.spec.containers[0].volumeMounts[?(@.name==\"" <> mountName <> "\")].mountPath}"
      ]

requirePodByPrefix :: ClusterState -> String -> String -> IO String
requirePodByPrefix state namespaceName prefixValue = do
  maybePod <- findPodByPrefix state namespaceName prefixValue
  case maybePod of
    Just podName -> pure podName
    Nothing -> fail ("did not find pod with prefix " <> prefixValue)

findPodByPrefix :: ClusterState -> String -> String -> IO (Maybe String)
findPodByPrefix state namespaceName prefixValue = do
  podNames <-
    filter (not . null) . map trim . lines
      <$> kubectlOutputForState
        state
        ["-n", namespaceName, "get", "pods", "--no-headers", "-o", "custom-columns=:metadata.name"]
  pure (find (isPrefixOf prefixValue) podNames)

requireReadyEnginePodNode :: ClusterState -> IO (String, String)
requireReadyEnginePodNode state = do
  maybePodNode <- findReadyEnginePodNode state
  case maybePodNode of
    Just podNode -> pure podNode
    Nothing -> fail "did not find a Ready infernix-engine pod with an assigned node"

findReadyEnginePodNode :: ClusterState -> IO (Maybe (String, String))
findReadyEnginePodNode state = do
  podLines <-
    lines
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "pods",
          "-l",
          "app.kubernetes.io/name=infernix-engine",
          "-o",
          "jsonpath={range .items[*]}{.metadata.name}{\"\\t\"}{.spec.nodeName}{\"\\t\"}{.status.phase}{\"\\t\"}{range .status.conditions[?(@.type==\"Ready\")]}{.status}{end}{\"\\n\"}{end}"
        ]
  pure $
    case find isReadyEnginePodNode (mapMaybe parseReadyPodNode podLines) of
      Just (podName, nodeName, _, _) -> Just (podName, nodeName)
      Nothing -> Nothing

parseReadyPodNode :: String -> Maybe (String, String, String, String)
parseReadyPodNode lineValue =
  case splitTabs lineValue of
    [podName, nodeName, phaseValue, readyValue]
      | not (null podName) && not (null nodeName) ->
          Just (podName, nodeName, phaseValue, readyValue)
    _ -> Nothing

isReadyEnginePodNode :: (String, String, String, String) -> Bool
isReadyEnginePodNode (_, _, phaseValue, readyValue) =
  phaseValue == "Running" && readyValue == "True"

waitForPodByPrefix :: ClusterState -> String -> String -> Maybe String -> IO String
waitForPodByPrefix state namespaceName prefixValue maybePreviousPod = go (72 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = fail ("timed out waiting for pod with prefix " <> prefixValue)
      | otherwise = do
          maybePod <- findPodByPrefix state namespaceName prefixValue
          case maybePod of
            Just podName
              | maybePreviousPod /= Just podName -> do
                  waitForPodReady state namespaceName podName
                  pure podName
            _ -> do
              threadDelay 5000000
              go (remainingAttempts - 1)

waitForPodReady :: ClusterState -> String -> String -> IO ()
waitForPodReady state namespaceName podName =
  runKubectl
    state
    [ "-n",
      namespaceName,
      "wait",
      "--for=condition=Ready",
      "pod/" <> podName,
      "--timeout=900s"
    ]

splitTabs :: String -> [String]
splitTabs [] = [""]
splitTabs value =
  case break (== '\t') value of
    (segment, '\t' : rest) -> segment : splitTabs rest
    (segment, _) -> [segment]
