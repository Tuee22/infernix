{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TemplateHaskell #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (IOException, SomeException, bracket, bracketOnError, displayException, try)
import Control.Monad (forM, forM_, unless, void, when)
import Data.Aeson ((.:), (.=))
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.ByteString qualified as ByteString
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.ByteString.Lazy.Char8 qualified as LazyByteStringChar8
import Data.Char (isAsciiUpper)
import Data.FileEmbed (embedFile)
import Data.List (find, intercalate, isInfixOf, isPrefixOf, isSuffixOf, nub, partition, sort)
import Data.List.NonEmpty qualified as NonEmpty
import Data.Map.Strict qualified as Map
import Data.Maybe (isJust, isNothing, mapMaybe)
import Data.Set qualified as Set
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (getCurrentTime)
import Data.Time.Clock.POSIX (getPOSIXTime)
import Infernix.CLI qualified as CLI
import Infernix.Cluster
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.Conversation.Topic qualified as ConversationTopic
import Infernix.DescriptorSpace (establishBoundedDescriptorSpace)
import Infernix.Error
  ( bracketPreservingPrimary,
    finallyPreservingPrimary,
    runCleanupsPreservingFailures,
  )
import Infernix.ExecutionPlan qualified as ExecutionPlan
import Infernix.HostTools qualified as HostTools
import Infernix.Models
  ( engineBindingForSelectedEngine,
    engineNameForSelectedEngine,
    expectedDaemonLocationForRuntime,
    expectedInferenceExecutorLocationForRuntime,
    findModel,
    resultFamilyForDescriptor,
  )
import Infernix.Objects.Layout qualified as ObjLayout
import Infernix.Objects.Presigned qualified as Presigned
import Infernix.Runtime.Pulsar
  ( PulsarTransport (..),
    PulsarWebSocketBase (..),
    RawTopicMessage (..),
    compactTopicAndWait,
    discoverPulsarTransport,
    publishDemoClientMessage,
    publishInferenceRequest,
    rawTopicInferenceRequestIds,
    readNamespaceCompactionThreshold,
    readPublishedInferenceResultMaybe,
    readRawTopicPayloads,
    serviceConsumerName,
    serviceReadinessMarkerPath,
  )
import Infernix.Substrate (decodeCompiledRuntimePlanFile)
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
    getSocketName,
    listen,
    setSocketOption,
    socket,
    tupleToHostAddress,
  )
import Network.WebSockets qualified as WebSockets
import System.Directory
import System.Environment (getArgs, getExecutablePath, withArgs)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (BufferMode (LineBuffering), IOMode (WriteMode), hClose, hFlush, hSetBuffering, openFile, stdout)
import System.IO.Error (catchIOError, isAlreadyInUseError, isDoesNotExistError)
import System.Posix.Process (ProcessStatus (..), forkProcessWithUnmask, getProcessGroupID, getProcessStatus)
import System.Posix.Signals (sigKILL, signalProcess)
import System.Posix.Types (ProcessID)
import System.Process
  ( CreateProcess (cwd, std_err, std_out),
    ProcessHandle,
    StdStream (UseHandle),
    createProcess,
    getProcessExitCode,
    proc,
    readProcess,
    readProcessWithExitCode,
    terminateProcess,
    waitForProcess,
  )
import System.Timeout (timeout)

data CompactedTopicMessage = CompactedTopicMessage
  { compactedTopicMessageKey :: Maybe Text.Text,
    compactedTopicMessagePayload :: ByteString.ByteString
  }
  deriving (Eq, Show)

data IntegrationPulsarEnvelope = IntegrationPulsarEnvelope
  { integrationEnvelopeMessageId :: Text.Text,
    integrationEnvelopePayload :: Text.Text
  }
  deriving (Eq, Show)

instance Aeson.FromJSON IntegrationPulsarEnvelope where
  parseJSON = Aeson.withObject "IntegrationPulsarEnvelope" $ \value ->
    IntegrationPulsarEnvelope
      <$> value .: "messageId"
      <*> value .: "payload"

main :: IO ()
main = do
  arguments <- getArgs
  case arguments of
    marker : cliArguments
      | marker == integrationCliSelfExecMarker ->
          withArgs cliArguments CLI.main
    _ -> do
      -- Test images spawn self-exec children through the same close_fds
      -- kernels the production binary uses, so they bound their descriptor
      -- space first. See "Infernix.DescriptorSpace".
      _ <- establishBoundedDescriptorSpace
      Subprocess.dispatchInternalSubprocessMode
      integrationTestRoot <- testRootPath "integration"
      withTestRoot integrationTestRoot $ do
        paths <- Config.discoverPaths
        runtimeModes <- integrationRuntimeModes
        mapM_ (exerciseRuntimeMode paths) runtimeModes
        mapM_ (validateDemoUiDisabled paths) runtimeModes
        case runtimeModes of
          runtimeMode : _
            | Config.controlPlaneContext paths /= Config.OuterContainer ->
                validateEdgePortConflictAndRediscovery paths runtimeMode
          _ -> pure ()
        putStrLn "integration tests passed"

-- The integration image already contains the exact CLI modules under test.
-- A fixed self-exec marker re-enters that CLI without starting a nested Cabal
-- build or discovering a second executable through ambient PATH.
integrationCliSelfExecMarker :: String
integrationCliSelfExecMarker = "__infernix_integration_cli_self_exec"

integrationRuntimeModes :: IO [RuntimeMode]
integrationRuntimeModes =
  (: []) <$> Config.resolveRuntimeMode Nothing

withClusterLifecycle :: RuntimeMode -> IO a -> IO a
withClusterLifecycle runtimeMode action =
  ( do
      clusterUpHarness (Just runtimeMode)
      action
  )
    `finallyPreservingPrimary` clusterDownHarness (Just runtimeMode)

exerciseRuntimeMode :: Paths -> RuntimeMode -> IO ()
exerciseRuntimeMode paths runtimeMode = do
  materializeGeneratedSubstrate runtimeMode True
  withClusterLifecycle runtimeMode $ do
    withRuntimeServiceDaemonIfNeeded paths runtimeMode $ do
      reportStep ("cluster state reload: " <> showRuntimeMode runtimeMode)
      maybeState <- loadClusterState paths
      state <- maybe (fail "cluster state was not available after cluster up") pure maybeState
      compiledPlan <- requireCompiledRuntimePlanFile (generatedDemoConfigPath state)
      reportStep ("demo config loaded: " <> showRuntimeMode runtimeMode)
      let activeModels = ExecutionPlan.compiledPlanConfiguredModels compiledPlan
          activeModelIds = map (Text.unpack . modelId) activeModels
          expectedDaemonLocation = Text.unpack (expectedDaemonLocationForRuntime runtimeMode)
          expectedInferenceExecutorLocation = Text.unpack (expectedInferenceExecutorLocationForRuntime runtimeMode)
          expectedDispatchMode = expectedInferenceDispatchMode runtimeMode
      representativeModelId <- representativeModelForRuntime runtimeMode activeModels
      assert (clusterPresent state) ("cluster up records cluster presence for " <> showRuntimeMode runtimeMode)
      assertClusterServiceDeployment state
      let baseUrl = routeBaseUrl paths state
      reportStep ("route probes: " <> showRuntimeMode runtimeMode)
      homeResponse <- httpGet (baseUrl <> "/")
      publicationResponse <- httpGet (baseUrl <> "/api/publication")
      demoConfigResponse <- waitForRoutedDemoConfig paths state
      routedDemoConfig <- requireJsonDemoConfig demoConfigResponse
      modelsResponse <- httpGet (baseUrl <> "/api/models")
      (harborPortalStatus, _) <- httpGetWithStatus (baseUrl <> "/harbor")
      (harborApiStatus, _) <- httpGetWithStatus (baseUrl <> "/harbor/api/v2.0/projects")
      (pulsarAdminStatus, _) <- httpGetWithStatus (baseUrl <> "/pulsar/admin/admin/v2/clusters")
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
      assertRoutedDaemonSplit runtimeMode compiledPlan
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
      assert
        (harborPortalStatus `elem` [401, 403])
        "harbor portal route is gated by the operator Keycloak JWT edge policy when demo_ui is enabled (401 unauthenticated)"
      assert
        (harborApiStatus `elem` [401, 403])
        "harbor API route is gated by the operator Keycloak JWT edge policy when demo_ui is enabled (401 unauthenticated)"
      assert
        (not (any ((== "/minio/s3") . path) (routes state)))
        "Phase 3 Sprint 3.13: the /minio/s3 external gateway route is removed from the published route inventory"
      assert
        (pulsarAdminStatus `elem` [401, 403])
        "pulsar admin route is gated by the operator Keycloak JWT edge policy when demo_ui is enabled (401 unauthenticated)"
      assert
        (pulsarHttpStatus `elem` [401, 403])
        "pulsar websocket route is gated by the operator Keycloak JWT edge policy when demo_ui is enabled (401 unauthenticated)"
      reportStep ("per-model inference: " <> showRuntimeMode runtimeMode)
      validateCatalogModelInferenceForRuntime paths state runtimeMode compiledPlan
      reportStep ("cache lifecycle: " <> showRuntimeMode runtimeMode)
      -- Phase 9 Sprint 9.3: @GET /api/cache@ exposes cluster-wide model-cache
      -- state, so it is now admin-gated (`withAdminRequest`) alongside the
      -- @/api/cache/{evict,rebuild}@ mutations. Like the Harbor / Pulsar Admin
      -- operator routes above, the integration lane proves the gate is present
      -- by asserting an unauthenticated read is rejected 401; the
      -- admin-authenticated 2xx read (and the non-admin 403) is proven by
      -- routed Playwright (Sprint 9.8). The engine-pod manifest contents were
      -- already invisible from the demo pod after the Sprint 7.7 daemon split.
      (cacheStatusCode, _) <- httpGetWithStatus (baseUrl <> "/api/cache")
      assert
        (cacheStatusCode == 401)
        "Phase 9 Sprint 9.3: GET /api/cache is admin-gated and rejects an unauthenticated read with 401"

      reportStep ("service runtime loop: " <> showRuntimeMode runtimeMode)
      ensureLinuxGpuRepresentativeEngineDeployment paths runtimeMode activeModels representativeModelId
      validateServiceRuntimeLoop paths state runtimeMode compiledPlan representativeModelId

      reportStep ("durable Pulsar topic families: " <> showRuntimeMode runtimeMode)
      ensureLinuxGpuRepresentativeEngineDeployment paths runtimeMode activeModels representativeModelId
      validateDurableTopicFamilyRoundTrips paths runtimeMode representativeModelId

      -- Phase 4 Sprint 4.34 retired the Apple host-engine coexistence case with
      -- the engine-lock waiver that made it runnable. It asserted that two engine
      -- daemons on one machine share a `Shared` subscription; one engine process
      -- per machine is a correctness rule, so that is now a refusal rather than a
      -- property. The backpressure case survives because it is about broker
      -- permits, not about two engines on one box.
      when (requiresHostServiceHarness paths runtimeMode) $ do
        reportStep ("apple shared subscription backlog backpressure: " <> showRuntimeMode runtimeMode)
        validateAppleSharedSubscriptionBackpressure paths compiledPlan

      -- Phase 6 Sprint 6.47 retired the failure-injection tail that used to run
      -- here: frontend pod replacement, coordinator failover, engine pod
      -- replacement, engine node drain, model-bootstrap failover/deduplication,
      -- Harbor recovery, MinIO durability, routed Pulsar recovery, and Postgres
      -- failover. Every one of them asserted a recovery property of a replicated
      -- topology that no longer exists: one process per role per machine and one
      -- instance per platform service means there is no surviving replica to
      -- promote, and instance loss is restore-from-backup. **This reduces what a
      -- green run proves**, and that reduction is recorded in
      -- DEVELOPMENT_PLAN/legacy-tracking-for-deletion.md rather than presented
      -- as a coverage-neutral cleanup.
      --
      -- What stays, and why each is not an HA property:
      --   * pool placement — the engine-pool graph, not recovery;
      --   * shared-subscription backpressure — broker permits over a test-owned
      --     subscription with synthetic consumers; it injects no failure, and
      --     the collapsed topology does not invalidate it;
      --   * multi-user throughput — no failure injection at all;
      --   * Postgres lifecycle rebinding — storage determinism (PV inventory and
      --     PVC rebinding identity across a lifecycle cycle), which is Phase 2
      --     doctrine;
      --   * the no-Pending-replica check — Phase 3 Sprint 3.16's positive proof.
      when (runtimeMode == LinuxCpu) $ do
        reportStep "linux engine pool placement"
        validateLinuxEnginePoolPlacement state runtimeMode compiledPlan
        reportStep "linux shared subscription backlog backpressure"
        validateLinuxSharedSubscriptionBackpressure paths runtimeMode compiledPlan
        reportStep "multi-user durable prompt throughput"
        validateMultiUserDurablePromptThroughput paths runtimeMode representativeModelId
        reportStep "postgres lifecycle rebinding"
        validatePostgresLifecycleRebinding paths runtimeMode state
        -- Phase 3 Sprint 3.16: the required pod anti-affinity is deleted with
        -- the topology it constrained, so this case is inverted rather than
        -- retired. What is asserted now is the observable proof that the
        -- constraint is gone rather than merely unsatisfied: every deployed
        -- workload is fully scheduled, with no `Pending` replica anywhere in
        -- the platform namespace. A leftover anti-affinity rule would show up
        -- here as exactly the `Pending` engine replica the retired case used to
        -- require.
        reportStep "single-node topology schedules every workload"
        validateNoPendingWorkloadReplicas state

      statusOutput <- captureInfernixOutput ["cluster", "status"]
      assert ("clusterPresent: True" `isInfixOf` statusOutput) "cluster status reports the cluster presence"
      assert (("runtimeMode: " <> showRuntimeMode runtimeMode) `isInfixOf` statusOutput) "cluster status reports the runtime mode"
      assert ("lifecycleStatus: idle" `isInfixOf` statusOutput) "cluster status reports idle lifecycle state after successful reconcile"
      assert (("publicationInferenceDispatchMode: " <> expectedDispatchMode) `isInfixOf` statusOutput) "cluster status reports the inference dispatch mode"
      assertHostBatchStatus runtimeMode statusOutput
      assert ("publicationStatePath: " `isInfixOf` statusOutput) "cluster status reports the publication state path"
      assert ("kubernetesNodeCount: 0" `notElemString` statusOutput) "cluster status reports reachable Kubernetes nodes"
      assert ("kubernetesPodCount: 0" `notElemString` statusOutput) "cluster status reports reachable Kubernetes pods"

    when (usesDetachedRetainedSnapshot paths runtimeMode) $ do
      reportStep ("detached retained snapshot replay: " <> showRuntimeMode runtimeMode)
      validateDetachedRetainedSnapshotReplay paths runtimeMode

  maybeDownState <- loadClusterState paths
  assert (maybe False (not . clusterPresent) maybeDownState) "cluster down records cluster absence"
  downStatusOutput <- captureInfernixOutput ["cluster", "status"]
  assert ("clusterPresent: False" `isInfixOf` downStatusOutput) "cluster status reports cluster absence after down"
  assert ("lifecyclePhase: cluster-absent" `isInfixOf` downStatusOutput) "cluster status reports the idle absent lifecycle phase after down"

validateCatalogModelInference ::
  Paths ->
  ClusterState ->
  RuntimeMode ->
  ExecutionPlan.CompiledRuntimePlan ->
  String ->
  IO ()
validateCatalogModelInference paths state runtimeMode compiledPlan modelIdValue = do
  model <-
    case findModel runtimeMode (Text.pack modelIdValue) of
      Just descriptor -> pure descriptor
      Nothing ->
        fail ("model " <> modelIdValue <> " is not in the " <> showRuntimeMode runtimeMode <> " catalog")
  maybeInputObjectRef <- ensureCatalogInputObject paths state runtimeMode model
  let requestUserIdValue = "integration-user"
      requestContextIdValue = Text.pack ("catalog-" <> sanitizeFileToken modelIdValue)
  requestIdValue <-
    publishInferenceRequest
      paths
      compiledPlan
      InferenceRequest
        { requestModelId = Text.pack modelIdValue,
          inputText = Text.pack ("integration coverage for " <> modelIdValue),
          inputObjectRef = maybeInputObjectRef,
          requestUserId = Just requestUserIdValue,
          requestContextId = Just requestContextIdValue
        }
  maybeResult <- waitForPublishedResult paths compiledPlan requestIdValue
  case maybeResult of
    -- Phase 6 Sprint 6.37: a missing result on apple-silicon is the OS-OOM-kill
    -- symptom (the on-host daemon died before publishing). The Phase 4 Sprint
    -- 4.26 admission control makes an over-budget model publish a clean
    -- status=failed instead, so a truly missing result now means a stall or a
    -- SIGKILL — never a fabricated pass — and is named as such.
    Nothing ->
      fail
        ( "service daemon did not publish a result for "
            <> modelIdValue
            <> " (apple-silicon: an OS OOM-kill or stall, not a clean fail-closed;"
            <> " Phase 4 Sprint 4.26 admission control must fail an over-budget"
            <> " model as a clean status=failed with a result)"
        )
    Just resultValue -> do
      assert
        (resultModelId resultValue == Text.pack modelIdValue)
        ("inference returns the selected model id for " <> modelIdValue)
      assert
        (resultRuntimeMode resultValue == runtimeMode)
        ("service daemon preserves the runtime mode in published results for " <> modelIdValue)
      -- Phase 4 Sprint 4.34: admission now happens on the engine, so the
      -- harness states its expectation as a prediction from the declared
      -- budget and holds the engine's published result to it. The engine, not
      -- this process, is the authority on whether the model fits.
      case ExecutionPlan.predictedAdmissionRejection compiledPlan (Text.pack modelIdValue) of
        Just expectedError -> do
          assert
            (status resultValue == "failed")
            "a model the executing machine cannot fund publishes a failed terminal result"
          assert
            (inferenceError (payload resultValue) == Just expectedError)
            "a model the executing machine cannot fund publishes the engine's typed admission error"
          assert
            (isNothing (inlineOutput (payload resultValue)) && isNothing (objectRef (payload resultValue)))
            "a model the executing machine cannot fund does not masquerade as real output"
          putStrLn
            ( "resource memory admission fail-closed for "
                <> modelIdValue
                <> ": "
                <> show expectedError
            )
        Nothing -> do
          assert
            (status resultValue == "completed")
            ( "inference completes for "
                <> modelIdValue
                <> failurePayloadSuffix (payload resultValue)
            )
          -- Phase 6 Sprint 6.2: assert the per-family real-output result
          -- contract, dispatched on ResultFamily (shape + type, never golden
          -- strings). One DRY suite reads the active substrate's catalog and
          -- traverses the README rows; the assertions pass only when a real
          -- engine ran on cohort hardware (Section P: results name the single
          -- substrate exercised).
          assertResultFamilyContract (resultFamilyForDescriptor model) modelIdValue (payload resultValue)
          -- Phase 4 Sprint 4.23: fail-closed object-ref check. The status ==
          -- "completed" assertion above already fails the row on status=failed
          -- (realness is the engine's job). For the artifact families we add a
          -- light existence/non-empty fetch of the returned object reference via
          -- the live MinIO port-forward (plus a magic-bytes container probe), but
          -- never assert dimensions / stem count / sample rate.
          assertResultObjectRefFetchable
            paths
            state
            (resultFamilyForDescriptor model)
            modelIdValue
            (Just (requestUserIdValue, requestContextIdValue))
            (payload resultValue)

-- | Phase 4 Sprint 4.23 — for artifact result families, fetch the returned
-- object reference through the live MinIO port-forward and assert it exists
-- and is non-empty, with a best-effort container magic-bytes probe. The text
-- families carry no object reference and are skipped. We never inspect the
-- artifact's internal shape (that is the engine's realness contract).
assertResultObjectRefFetchable :: Paths -> ClusterState -> ResultFamily -> String -> Maybe (Text.Text, Text.Text) -> ResultPayload -> IO ()
assertResultObjectRefFetchable paths state resultFamily modelIdValue expectedOwnership payloadValue
  | not (resultFamilyIsArtifact resultFamily) = pure ()
  | otherwise =
      case objectRef payloadValue of
        Nothing ->
          fail ("artifact family result for " <> modelIdValue <> " carried no object reference to fetch")
        Just ref -> do
          assertGeneratedObjectRefOwnership expectedOwnership ref
          fetched <- fetchObjectRefBytes paths state ref
          assert
            (not (ByteString.null fetched))
            ("returned object ref " <> Text.unpack ref <> " for " <> modelIdValue <> " is fetchable and non-empty")
          assert
            (objectMagicBytesPlausible ref fetched)
            ("returned object ref " <> Text.unpack ref <> " for " <> modelIdValue <> " starts with a plausible container signature")

assertGeneratedObjectRefOwnership :: Maybe (Text.Text, Text.Text) -> Text.Text -> IO ()
assertGeneratedObjectRefOwnership Nothing _ = pure ()
assertGeneratedObjectRefOwnership (Just (userIdText, contextIdText)) ref =
  case Text.breakOn "/" ref of
    (bucket, keyWithSlash)
      | not (Text.null keyWithSlash) -> do
          let objectKeyValue = Text.drop 1 keyWithSlash
              expectedPrefix =
                ObjLayout.generatedObjectPrefix
                  (Contracts.UserId userIdText)
                  (Contracts.ContextId contextIdText)
          assert
            (bucket == "infernix-demo-objects" && expectedPrefix `Text.isPrefixOf` objectKeyValue)
            ("generated artifact object ref is scoped to " <> Text.unpack expectedPrefix <> ": " <> Text.unpack ref)
    _ -> fail ("generated artifact object reference is not bucket/key: " <> Text.unpack ref)

-- | Fetch the bytes of an @infernix-demo-objects@ object reference
-- (@bucket\/key@) through a presigned GET minted against the live MinIO
-- port-forward.
fetchObjectRefBytes :: Paths -> ClusterState -> Text.Text -> IO ByteString.ByteString
fetchObjectRefBytes paths state ref =
  case Text.breakOn "/" ref of
    (bucket, keyWithSlash)
      | not (Text.null keyWithSlash) ->
          withMinioPortForward paths state $ \localPort -> do
            now <- getCurrentTime
            let objectReference =
                  Contracts.ObjectRef
                    { Contracts.objectBucket = bucket,
                      Contracts.objectKey = Text.drop 1 keyWithSlash
                    }
                presigned =
                  Presigned.PresignedUrlConfig
                    { Presigned.presignedScheme = "http",
                      Presigned.presignedEndpoint = Text.pack ("127.0.0.1:" <> show localPort),
                      Presigned.presignedPathPrefix = "",
                      Presigned.presignedRegion = "us-east-1",
                      Presigned.presignedAccessKeyId = "minioadmin",
                      Presigned.presignedSecretAccessKey = "minioadmin123",
                      Presigned.presignedExpirySeconds = 900,
                      Presigned.presignedSessionToken = Nothing
                    }
                signedUrl =
                  Text.unpack
                    (Presigned.unPresignedUrl (Presigned.presignedGetUrl presigned now objectReference))
                downloadPath =
                  buildRoot paths
                    </> "integration-result-"
                      <> sanitizeFileToken (Text.unpack ref)
            (exitCode, _stdout, stderrOutput) <-
              readProcessWithExitCode
                "curl"
                ["-fsS", "-o", downloadPath, signedUrl]
                ""
            case exitCode of
              ExitSuccess -> ByteString.readFile downloadPath
              _ ->
                fail
                  ( "failed to fetch returned object reference "
                      <> Text.unpack ref
                      <> ": "
                      <> stderrOutput
                  )
    _ -> fail ("returned object reference is not a bucket/key pair: " <> Text.unpack ref)

-- | Best-effort container magic-bytes probe keyed off the object-ref
-- extension. Recognizes PNG / RIFF (WAV) / MThd (MIDI) / PK (ZIP) / ftyp
-- (MP4). Unknown extensions (e.g. MusicXML) pass on non-empty bytes alone.
objectMagicBytesPlausible :: Text.Text -> ByteString.ByteString -> Bool
objectMagicBytesPlausible ref bytes
  | hasExtension ".png" = startsWith (ByteString.pack [137, 80, 78, 71])
  | hasExtension ".wav" = startsWith (ByteString8.pack "RIFF")
  | hasExtension ".mid" || hasExtension ".midi" = startsWith (ByteString8.pack "MThd")
  | hasExtension ".zip" = startsWith (ByteString8.pack "PK")
  | hasExtension ".mp4" = ByteString8.pack "ftyp" `ByteString.isInfixOf` ByteString.take 12 bytes
  | otherwise = not (ByteString.null bytes)
  where
    hasExtension extension = extension `Text.isSuffixOf` ref
    startsWith signature = signature `ByteString.isPrefixOf` bytes

validateCatalogModelInferenceForRuntime ::
  Paths ->
  ClusterState ->
  RuntimeMode ->
  ExecutionPlan.CompiledRuntimePlan ->
  IO ()
validateCatalogModelInferenceForRuntime paths state runtimeMode compiledPlan =
  validateCatalogModelInferenceWithPlan
    paths
    state
    runtimeMode
    compiledPlan
    (ExecutionPlan.compiledPlanConfiguredModels compiledPlan)

validateCatalogModelInferenceWithPlan ::
  Paths ->
  ClusterState ->
  RuntimeMode ->
  ExecutionPlan.CompiledRuntimePlan ->
  [ModelDescriptor] ->
  IO ()
validateCatalogModelInferenceWithPlan paths state runtimeMode compiledPlan activeModels =
  case runtimeMode of
    LinuxGpu -> validateLinuxGpuCatalogModelInferenceSerially paths state compiledPlan activeModels
    _ -> forM_ (map (Text.unpack . modelId) activeModels) (validateCatalogModelInference paths state runtimeMode compiledPlan)

validateLinuxGpuCatalogModelInferenceSerially ::
  Paths ->
  ClusterState ->
  ExecutionPlan.CompiledRuntimePlan ->
  [ModelDescriptor] ->
  IO ()
validateLinuxGpuCatalogModelInferenceSerially paths state compiledPlan activeModels = do
  let (pythonNativeModels, nativeModels) = partition linuxGpuModelUsesPythonNativeEngine activeModels
  pythonNativeDeployments <-
    forM pythonNativeModels $ \model -> do
      deploymentName <- requireLinuxGpuPerEngineDeploymentName model
      pure (model, deploymentName)
  let perEngineNames =
        sort
          . nub
          $ map snd pythonNativeDeployments
  prepareLinuxGpuEngineDeployment paths perEngineNames Nothing
  forM_ (map (Text.unpack . modelId) nativeModels) (validateCatalogModelInference paths state LinuxGpu compiledPlan)
  forM_ perEngineNames $ \engineName -> do
    reportStep ("linux-gpu per-engine deployment: " <> Text.unpack engineName)
    prepareLinuxGpuEngineDeployment paths perEngineNames (Just engineName)
    forM_
      [ Text.unpack (modelId model)
      | (model, deploymentName) <- pythonNativeDeployments,
        deploymentName == engineName
      ]
      (validateCatalogModelInference paths state LinuxGpu compiledPlan)
  prepareLinuxGpuEngineDeployment paths perEngineNames Nothing

ensureLinuxGpuRepresentativeEngineDeployment :: Paths -> RuntimeMode -> [ModelDescriptor] -> String -> IO ()
ensureLinuxGpuRepresentativeEngineDeployment paths runtimeMode activeModels representativeModelId =
  when (runtimeMode == LinuxGpu) $ do
    let pythonNativeModels = filter linuxGpuModelUsesPythonNativeEngine activeModels
    pythonNativeDeployments <-
      forM pythonNativeModels $ \model -> do
        deploymentName <- requireLinuxGpuPerEngineDeploymentName model
        pure (model, deploymentName)
    let perEngineNames =
          sort
            . nub
            $ map snd pythonNativeDeployments
    case find
      ((== Text.pack representativeModelId) . modelId . fst)
      pythonNativeDeployments of
      Just (_, deploymentName) ->
        prepareLinuxGpuEngineDeployment paths perEngineNames (Just deploymentName)
      Nothing ->
        prepareLinuxGpuEngineDeployment paths perEngineNames Nothing

ensureCatalogInputObject :: Paths -> ClusterState -> RuntimeMode -> ModelDescriptor -> IO (Maybe Text.Text)
ensureCatalogInputObject paths state runtimeMode model =
  case sampleInputForModel model of
    Nothing -> pure Nothing
    Just (suffix, payloadBytes) -> do
      let objectReference =
            Contracts.ObjectRef
              { Contracts.objectBucket = "infernix-demo-objects",
                Contracts.objectKey =
                  Text.concat
                    [ "integration-inputs/",
                      runtimeModeId runtimeMode,
                      "/",
                      modelId model,
                      suffix
                    ]
              }
      uploadIntegrationInputObject paths state objectReference payloadBytes
      pure (Just (objectRefText objectReference))

-- | Phase 4 Sprint 4.23 — real per-family input fixtures. The degenerate
-- silence-WAV / 1×1-PNG inputs are replaced by programmatically generated
-- real-signal fixtures (deterministic, so byte-identical across substrates):
-- a non-silent speech-like formant sweep for transcription, a multi-tone
-- music mixture for source separation, an instrument-like arpeggio phrase for
-- audio→MIDI / music transcription, and a real single-staff score image
-- (PNG, not MusicXML) for OMR. Routing dispatches purely on the row's
-- 'ResultFamily'; the text families stay prompt-only.
sampleInputForModel :: ModelDescriptor -> Maybe (Text.Text, ByteString.ByteString)
sampleInputForModel model =
  case resultFamilyForDescriptor model of
    SpeechTranscription -> Just (".wav", speechWavBytes)
    SourceSeparation -> Just (".wav", separationMixtureWavBytes)
    AudioToMidi -> Just (".wav", instrumentArpeggioWavBytes)
    MusicTranscription -> Just (".wav", instrumentArpeggioWavBytes)
    OpticalMusicRecognition -> Just (".png", scoreImagePngBytes)
    LlmText -> Nothing
    ImageGeneration -> Nothing
    VideoGeneration -> Nothing
    AudioGeneration -> Nothing

uploadIntegrationInputObject :: Paths -> ClusterState -> Contracts.ObjectRef -> ByteString.ByteString -> IO ()
uploadIntegrationInputObject paths state objectReference payloadBytes = do
  withMinioPortForward paths state $ \localPort -> do
    now <- getCurrentTime
    let presigned =
          Presigned.PresignedUrlConfig
            { Presigned.presignedScheme = "http",
              Presigned.presignedEndpoint = Text.pack ("127.0.0.1:" <> show localPort),
              Presigned.presignedPathPrefix = "",
              Presigned.presignedRegion = "us-east-1",
              Presigned.presignedAccessKeyId = "minioadmin",
              Presigned.presignedSecretAccessKey = "minioadmin123",
              Presigned.presignedExpirySeconds = 900,
              Presigned.presignedSessionToken = Nothing
            }
        signedUrl =
          Text.unpack
            (Presigned.unPresignedUrl (Presigned.presignedPutUrl presigned now objectReference))
        samplePath =
          buildRoot paths
            </> "integration-input-"
              <> sanitizeFileToken (Text.unpack (Contracts.objectKey objectReference))
    ByteString.writeFile samplePath payloadBytes
    (exitCode, _stdout, stderrOutput) <-
      readProcessWithExitCode
        "curl"
        ["-fsS", "-X", "PUT", "--data-binary", "@" <> samplePath, signedUrl]
        ""
    case exitCode of
      ExitSuccess -> pure ()
      _ ->
        fail
          ( "failed to upload integration input object "
              <> Text.unpack (objectRefText objectReference)
              <> ": "
              <> stderrOutput
          )

withMinioPortForward :: Paths -> ClusterState -> (Int -> IO a) -> IO a
withMinioPortForward paths state action = do
  localPort <- allocateLoopbackPort
  let logPath = buildRoot paths </> "minio-port-forward-" <> show localPort <> ".log"
      loadProcess =
        hostToolProcessForPaths
          paths
          HostTools.HostKubectl
          ( ["--kubeconfig", kubeconfigPath state]
              <> ["-n", "platform", "port-forward", "svc/infernix-minio", show localPort <> ":9000"]
          )
  withLoggedProcess logPath loadProcess $ \processHandle -> do
    waitForMinioPortForward localPort processHandle logPath
    action localPort

allocateLoopbackPort :: IO Int
allocateLoopbackPort =
  bracket (socket AF_INET Stream defaultProtocol) close $ \socketValue -> do
    setSocketOption socketValue ReuseAddr 1
    bind socketValue (SockAddrInet 0 (tupleToHostAddress (127, 0, 0, 1)))
    socketAddress <- getSocketName socketValue
    case socketAddress of
      SockAddrInet portNumber _ -> pure (fromIntegral portNumber)
      _ -> fail ("unexpected socket address for loopback port allocation: " <> show socketAddress)

hostToolProcessForPaths :: Paths -> HostTools.HostTool -> [String] -> IO CreateProcess
hostToolProcessForPaths paths tool args =
  case pathsHostConfig paths of
    Just hostConfig -> pure (HostTools.hostToolProcess hostConfig tool args)
    Nothing -> do
      toolPath <- requireFallbackHostTool tool
      pure (proc toolPath args)

requireFallbackHostTool :: HostTools.HostTool -> IO FilePath
requireFallbackHostTool tool =
  go (HostTools.hostToolFallbackCandidates tool)
  where
    go [] =
      fail
        ( "required host tool is unavailable: "
            <> Text.unpack (HostTools.hostToolName tool)
        )
    go (candidate : rest) = do
      exists <- doesFileExist candidate
      if exists
        then pure candidate
        else go rest

waitForMinioPortForward :: Int -> ProcessHandle -> FilePath -> IO ()
waitForMinioPortForward localPort processHandle logPath =
  go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = do
          logContents <- readFileIfPresent logPath
          fail
            ( "timed out waiting for kubectl port-forward to MinIO on 127.0.0.1:"
                <> show localPort
                <> "\n"
                <> logContents
            )
      | otherwise = do
          maybeExitCode <- getProcessExitCode processHandle
          case maybeExitCode of
            Just exitCode -> do
              logContents <- readFileIfPresent logPath
              fail
                ( "kubectl port-forward to MinIO exited before becoming ready ("
                    <> show exitCode
                    <> ")\n"
                    <> logContents
                )
            Nothing -> do
              ready <- minioPortForwardReady localPort
              if ready
                then pure ()
                else do
                  threadDelay 500000
                  go (remainingAttempts - 1)

minioPortForwardReady :: Int -> IO Bool
minioPortForwardReady localPort = do
  (exitCode, _stdoutOutput, _stderrOutput) <-
    readProcessWithExitCode
      "curl"
      ["-fsS", "--max-time", "2", "http://127.0.0.1:" <> show localPort <> "/minio/health/live"]
      ""
  pure (exitCode == ExitSuccess)

readFileIfPresent :: FilePath -> IO String
readFileIfPresent path =
  catchIOError
    (readFile path)
    ( \err ->
        if isDoesNotExistError err
          then pure ""
          else ioError err
    )

objectRefText :: Contracts.ObjectRef -> Text.Text
objectRefText objectReference =
  Contracts.objectBucket objectReference <> "/" <> Contracts.objectKey objectReference

failurePayloadSuffix :: ResultPayload -> String
failurePayloadSuffix payloadValue =
  case (inferenceError payloadValue, inlineOutput payloadValue) of
    (Just errorValue, _) -> "; inferenceError: " <> show errorValue
    (Nothing, Just text) -> "; payload: " <> Text.unpack text
    (Nothing, Nothing) -> ""

sanitizeFileToken :: String -> String
sanitizeFileToken =
  map sanitize
  where
    sanitize character
      | character `elem` (['A' .. 'Z'] <> ['a' .. 'z'] <> ['0' .. '9'] <> ".-_") = character
      | otherwise = '-'

-- | Phase 4 Sprint 4.23 — a non-silent, speech-like mono 16 kHz fixture.
-- We synthesize a voiced source (a glottal-pulse-like sawtooth at a falling
-- pitch) shaped by a pair of formant resonances that glide across the
-- utterance, plus a light noise burst, so the decoder runs on real signal
-- rather than digital silence. This is intelligible-shaped, not genuinely
-- spoken; a real human utterance should be sourced for the cohort gate.
speechWavBytes :: ByteString.ByteString
speechWavBytes =
  encodePcm16Wav 16000 1 samples
  where
    sampleRate = 16000 :: Int
    durationSeconds = 1.6 :: Double
    sampleCount = round (durationSeconds * fromIntegral sampleRate) :: Int
    samples =
      [ amplitudeAt index | index <- [0 .. sampleCount - 1]
      ]
    amplitudeAt index =
      let t = fromIntegral index / fromIntegral sampleRate :: Double
          progress = t / durationSeconds
          -- Falling fundamental from 150 Hz to 95 Hz (a spoken-like contour).
          f0 = 150 - 55 * progress
          -- Sawtooth glottal source from summed harmonics.
          source =
            sum
              [ (1 / fromIntegral harmonic)
                  * sin (2 * pi * f0 * fromIntegral harmonic * t)
              | harmonic <- [1 .. 12 :: Int]
              ]
          -- Two formants gliding across the utterance (vowel-like timbre).
          formant1 = 500 + 300 * progress
          formant2 = 1500 + 700 * progress
          shaped =
            source
              * (0.6 + 0.4 * sin (2 * pi * formant1 * t))
              + 0.3 * source * sin (2 * pi * formant2 * t)
          -- Light aspiration noise from a cheap deterministic LCG.
          noise = deterministicNoise index * 0.08
          -- Soft fade in/out so we do not clip the WAV boundaries.
          envelope = min 1 (min (progress * 8) ((1 - progress) * 8))
       in clampToInt16 (0.5 * envelope * (shaped + noise))

-- | Phase 4 Sprint 4.23 — a real music-like mixture for source separation:
-- a sustained major triad (vocal/harmony stand-in), a low bass tone, and a
-- rhythmic percussive pulse, rendered 44.1 kHz stereo so Demucs / Open-Unmix
-- run on a genuine multi-source mixture instead of silence.
separationMixtureWavBytes :: ByteString.ByteString
separationMixtureWavBytes =
  encodePcm16Wav 44100 2 interleaved
  where
    sampleRate = 44100 :: Int
    durationSeconds = 2.0 :: Double
    sampleCount = round (durationSeconds * fromIntegral sampleRate) :: Int
    -- Interleave L/R; the chord leans left, the bass leans right so the
    -- stereo field is non-degenerate.
    interleaved =
      concat
        [ [leftAt index, rightAt index] | index <- [0 .. sampleCount - 1]
        ]
    leftAt index = clampToInt16 (0.32 * (chord index + 0.25 * pulse index + 0.5 * bass index))
    rightAt index = clampToInt16 (0.32 * (0.6 * chord index + 0.3 * pulse index + bass index))
    chord index =
      let t = timeOf index
       in sum [sin (2 * pi * freq * t) | freq <- [261.63, 329.63, 392.0]]
    bass index = sin (2 * pi * 82.41 * timeOf index)
    pulse index =
      let t = timeOf index
          -- A two-per-second percussive click train with a fast decay.
          beatPhase = fromIntegral (index `mod` (sampleRate `div` 2))
          decay = exp (negate beatPhase / 1200)
       in decay * sin (2 * pi * 1800 * t)
    timeOf index = fromIntegral index / fromIntegral sampleRate :: Double

-- | Phase 4 Sprint 4.23 — a real instrument-like phrase for audio→MIDI /
-- music transcription: a C-major arpeggio (C4 E4 G4 C5 G4 E4) of distinct
-- sustained sawtooth notes at 22.05 kHz mono, each with an attack/decay
-- envelope so the transcriber sees separable note onsets.
instrumentArpeggioWavBytes :: ByteString.ByteString
instrumentArpeggioWavBytes =
  encodePcm16Wav 22050 1 (concatMap noteSamples arpeggio)
  where
    sampleRate = 22050 :: Int
    noteSeconds = 0.4 :: Double
    noteSampleCount = round (noteSeconds * fromIntegral sampleRate) :: Int
    arpeggio = [261.63, 329.63, 392.0, 523.25, 392.0, 329.63] :: [Double]
    noteSamples frequency =
      [ noteAmplitude frequency index | index <- [0 .. noteSampleCount - 1]
      ]
    noteAmplitude frequency index =
      let t = fromIntegral index / fromIntegral sampleRate :: Double
          progress = fromIntegral index / fromIntegral noteSampleCount :: Double
          -- Sawtooth from summed harmonics gives an instrument-like timbre.
          tone =
            sum
              [ (1 / fromIntegral harmonic)
                  * sin (2 * pi * frequency * fromIntegral harmonic * t)
              | harmonic <- [1 .. 8 :: Int]
              ]
          -- Percussive attack, sustained body, gentle release.
          envelope = min 1 (progress * 12) * exp (negate progress * 1.5)
       in clampToInt16 (0.5 * envelope * tone)

-- | Deterministic [-1, 1) pseudo-noise from a 32-bit LCG seeded by the sample
-- index, so the fixture stays byte-identical across runs and substrates.
deterministicNoise :: Int -> Double
deterministicNoise index =
  let seeded = (1103515245 * (fromIntegral index + 12345) + 12345) `mod` 2147483648 :: Integer
   in fromIntegral seeded / 1073741824 - 1

-- | Clamp a normalized [-1, 1] amplitude into a signed 16-bit PCM sample.
clampToInt16 :: Double -> Int
clampToInt16 amplitude =
  max (-32768) (min 32767 (round (amplitude * 32767)))

-- | Build a canonical 16-bit PCM WAV from a flat (interleaved) sample list.
encodePcm16Wav :: Int -> Int -> [Int] -> ByteString.ByteString
encodePcm16Wav sampleRate channels samples =
  ByteString.concat
    [ ByteString8.pack "RIFF",
      littleEndian32 (36 + payloadLength),
      ByteString8.pack "WAVEfmt ",
      littleEndian32 16,
      littleEndian16 1,
      littleEndian16 channels,
      littleEndian32 sampleRate,
      littleEndian32 byteRate,
      littleEndian16 blockAlign,
      littleEndian16 16,
      ByteString8.pack "data",
      littleEndian32 payloadLength,
      sampleBytes
    ]
  where
    blockAlign = channels * 2
    byteRate = sampleRate * blockAlign
    sampleBytes = ByteString.concat (map (littleEndian16 . wrapInt16) samples)
    payloadLength = ByteString.length sampleBytes

-- | Phase 4 Sprint 4.23 / Wave K -- a real single-staff score IMAGE
-- (grayscale PNG). A genuine engraved score (treble clef, 4/4, two bars of
-- quarter notes) rendered by Verovio from MusicXML and rasterized to a 1400px
-- grayscale PNG (interline ~27px) that Audiveris transcribes to real
-- MusicXML. The prior synthetic 240x80 staff was below Audiveris's interline
-- and resolution threshold and was correctly rejected as un-transcribable.
-- Bytes are embedded from test/fixtures/omr-score.png at compile time.
scoreImagePngBytes :: ByteString.ByteString
scoreImagePngBytes = $(embedFile "test/fixtures/omr-score.png")

wrapInt16 :: Int -> Int
wrapInt16 value = value `mod` 65536

littleEndian16 :: Int -> ByteString.ByteString
littleEndian16 value =
  ByteString.pack [fromIntegral value, fromIntegral (value `div` 256)]

littleEndian32 :: Int -> ByteString.ByteString
littleEndian32 value =
  ByteString.pack
    [ fromIntegral value,
      fromIntegral (value `div` 256),
      fromIntegral (value `div` 65536),
      fromIntegral (value `div` 16777216)
    ]

linuxGpuModelUsesPythonNativeEngine :: ModelDescriptor -> Bool
linuxGpuModelUsesPythonNativeEngine model =
  maybe
    False
    engineBindingPythonNative
    (engineBindingForSelectedEngine LinuxGpu (selectedEngine model))

representativeModelForRuntime :: RuntimeMode -> [ModelDescriptor] -> IO String
representativeModelForRuntime runtimeMode activeModels =
  case runtimeMode of
    LinuxGpu ->
      case find (not . linuxGpuModelUsesPythonNativeEngine) activeModels of
        Just model -> pure (Text.unpack (modelId model))
        Nothing -> fallbackRepresentative
    _ -> fallbackRepresentative
  where
    fallbackRepresentative =
      case activeModels of
        model : _ -> pure (Text.unpack (modelId model))
        [] -> fail "generated demo config did not publish any models"

requireLinuxGpuPerEngineDeploymentName :: ModelDescriptor -> IO Text.Text
requireLinuxGpuPerEngineDeploymentName model =
  maybe
    ( fail
        ( "Linux GPU catalog model has no canonical per-engine deployment name: "
            <> Text.unpack (modelId model)
            <> " (selected engine "
            <> Text.unpack (selectedEngine model)
            <> ")"
        )
    )
    pure
    (engineNameForSelectedEngine LinuxGpu (selectedEngine model))

-- Sprint 6.43 (corrected 2026-08-02 by the final cross-phase review): this
-- rotates the shared engine Deployment and every per-engine Deployment between
-- replica counts, which is exactly the class of cluster mutation the
-- `ClusterMutating` position exists for. It previously ran outside
-- `withPersistedClusterMutation`, so a SIGKILL anywhere in the rotation left the
-- persisted state reading `ClusterReady` while the live cluster had engine
-- Deployments scaled to zero — the exact false steady-state the doctrine
-- forbids. The marker brackets the whole rotation so a killed run leaves a
-- detectable dirty cluster the next `cluster up` reconciles by scaling the
-- deployments back to their chart counts.
--
-- Phase 6 Sprint 6.47: this is now the suite's **only** integration exemplar of
-- the crash-safe cluster-mutation bracket. Its two former siblings — the
-- engine-deployment over-scale case and the node-drain case — were chaos cases
-- and were deleted with the replicated topology they asserted recovery for. The
-- doctrine outlives its examples, so it is re-exemplared here on a real non-HA
-- caller rather than left without one; the unit suite retains the bracket's own
-- crash/reconcile assertions independently of any cluster.
prepareLinuxGpuEngineDeployment :: Paths -> [Text.Text] -> Maybe Text.Text -> IO ()
prepareLinuxGpuEngineDeployment paths perEngineNames maybeEngineName = do
  mutationState <-
    maybe
      (fail "linux-gpu engine deployment rotation requires a freshly persisted cluster state")
      pure
      =<< loadClusterState paths
  withPersistedClusterMutation
    paths
    mutationState
    "linux-gpu-engine-deployment-rotation"
    ( "rotating the shared and per-engine linux-gpu engine Deployments to "
        <> maybe "the shared deployment" Text.unpack maybeEngineName
    )
    (\freshState -> rotateLinuxGpuEngineDeployments freshState perEngineNames maybeEngineName)

rotateLinuxGpuEngineDeployments :: ClusterState -> [Text.Text] -> Maybe Text.Text -> IO ()
rotateLinuxGpuEngineDeployments state perEngineNames maybeEngineName = do
  case maybeEngineName of
    Just _ ->
      runKubectl state ["-n", "platform", "scale", "deployment/infernix-engine", "--replicas=0"]
    Nothing ->
      pure ()
  forM_ perEngineNames $ \engineName -> do
    let replicas =
          case maybeEngineName of
            Just activeEngineName | activeEngineName == engineName -> "1"
            _ -> "0"
    runKubectl
      state
      [ "-n",
        "platform",
        "scale",
        "deployment/infernix-engine-" <> Text.unpack engineName,
        "--replicas=" <> replicas
      ]
  case maybeEngineName of
    Nothing -> do
      runKubectl state ["-n", "platform", "scale", "deployment/infernix-engine", "--replicas=1"]
      runKubectl state ["-n", "platform", "rollout", "status", "deployment/infernix-engine", "--timeout=900s"]
    Just activeEngineName ->
      runKubectl
        state
        [ "-n",
          "platform",
          "rollout",
          "status",
          "deployment/infernix-engine-" <> Text.unpack activeEngineName,
          "--timeout=900s"
        ]

-- | Phase 6 Sprint 6.2 — per-family result-shape contract. Text families
-- (LLM, speech transcription) carry a non-empty inline continuation; every
-- artifact family carries an @infernix-demo-objects@ object reference whose
-- key extension matches the family's artifact type. The deeper byte/dimension
-- checks (>= 2 separation stems, valid MIDI/MusicXML, image dimensions, audio
-- sample rate) run against the fetched artifact on cohort hardware.
assertResultFamilyContract :: ResultFamily -> String -> ResultPayload -> IO ()
assertResultFamilyContract resultFamily modelIdValue payloadValue
  | resultFamilyIsArtifact resultFamily =
      case objectRef payloadValue of
        Just ref -> do
          assert
            (isNothing (inlineOutput payloadValue))
            ("artifact family " <> familyLabel <> " does not return inline output for " <> modelIdValue)
          assert
            ("infernix-demo-objects/" `Text.isPrefixOf` ref)
            ("artifact family " <> familyLabel <> " writes to the infernix-demo-objects bucket for " <> modelIdValue)
          assert
            (any (`Text.isSuffixOf` ref) (expectedArtifactSuffixes resultFamily))
            ("artifact family " <> familyLabel <> " returns the expected artifact type for " <> modelIdValue)
        Nothing ->
          fail ("artifact family " <> familyLabel <> " must return an object reference for " <> modelIdValue)
  | otherwise =
      case inlineOutput payloadValue of
        Just text ->
          assert
            (not (Text.null (Text.strip text)) && isNothing (objectRef payloadValue))
            ("text family " <> familyLabel <> " returns a non-empty inline continuation for " <> modelIdValue)
        Nothing ->
          fail ("text family " <> familyLabel <> " must return inline output for " <> modelIdValue)
  where
    familyLabel = Text.unpack (resultFamilyId resultFamily)

expectedArtifactSuffixes :: ResultFamily -> [Text.Text]
expectedArtifactSuffixes resultFamily =
  case resultFamily of
    SourceSeparation -> [".zip"]
    AudioToMidi -> [".mid", ".midi"]
    MusicTranscription -> [".mid", ".midi", ".musicxml", ".xml"]
    ImageGeneration -> [".png"]
    VideoGeneration -> [".mp4"]
    AudioGeneration -> [".wav"]
    OpticalMusicRecognition -> [".mxl", ".musicxml", ".xml"]
    LlmText -> []
    SpeechTranscription -> []

assertHostBatchPublication :: RuntimeMode -> String -> IO ()
assertHostBatchPublication runtimeMode publicationResponse =
  assert
    (not ("hostInferenceBatchTopic" `isInfixOf` compact publicationResponse))
    ("publication omits legacy host inference batch topic metadata for " <> showRuntimeMode runtimeMode)

assertHostBatchStatus :: RuntimeMode -> String -> IO ()
assertHostBatchStatus runtimeMode statusOutput =
  assert
    (not ("publicationHostInferenceBatchTopic:" `isInfixOf` statusOutput))
    ("cluster status omits legacy inference batch handoff topic for " <> showRuntimeMode runtimeMode)

assertRoutedDaemonSplit :: RuntimeMode -> ExecutionPlan.CompiledRuntimePlan -> IO ()
assertRoutedDaemonSplit runtimeMode compiledPlan = do
  let coordinator = ExecutionPlan.compiledPlanCoordinatorDaemon compiledPlan
      engineDaemons = ExecutionPlan.compiledPlanEngineDaemons compiledPlan
      engineRoutes =
        concatMap
          (NonEmpty.toList . ExecutionPlan.compiledPlacementRoutes)
          (ExecutionPlan.compiledRuntimePlanPlacements compiledPlan)
      expectedEngineRequestTopics = map ExecutionPlan.engineRouteTopic engineRoutes
      actualEngineRequestTopics = concatMap ExecutionPlan.compiledDaemonRequestTopics engineDaemons
  assert
    (ExecutionPlan.compiledPlanRuntimeMode compiledPlan == runtimeMode)
    "compiled plan reports the exercised runtime mode"
  assert (ExecutionPlan.compiledDaemonRole coordinator == Coordinator) "compiled plan reports coordinator metadata"
  assert
    (ExecutionPlan.compiledDaemonRequestTopics coordinator == ExecutionPlan.compiledPlanRequestTopics compiledPlan)
    "coordinator consumes the substrate request topic"
  assert
    (not (null engineDaemons))
    ("compiled plan omits engine metadata for " <> showRuntimeMode runtimeMode)
  mapM_
    ( \engineDaemon ->
        assert
          (ExecutionPlan.compiledDaemonRole engineDaemon == Engine)
          "compiled plan reports engine metadata"
    )
    engineDaemons
  assert
    (not (null expectedEngineRequestTopics))
    "compiled placements have validated engine routes to consume"
  assert
    (all (`elem` actualEngineRequestTopics) expectedEngineRequestTopics)
    "compiled engine daemons include every validated placement route"

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

validateServiceRuntimeLoop ::
  Paths ->
  ClusterState ->
  RuntimeMode ->
  ExecutionPlan.CompiledRuntimePlan ->
  String ->
  IO ()
validateServiceRuntimeLoop paths state runtimeMode compiledPlan representativeModelId = do
  model <-
    case findModel runtimeMode (Text.pack representativeModelId) of
      Just descriptor -> pure descriptor
      Nothing ->
        fail ("model " <> representativeModelId <> " is not in the " <> showRuntimeMode runtimeMode <> " catalog")
  maybeInputObjectRef <- ensureCatalogInputObject paths state runtimeMode model
  let requestUserIdValue = "service-loop-user"
      requestContextIdValue = Text.pack ("service-" <> sanitizeFileToken representativeModelId)
  requestIdValue <-
    publishInferenceRequest
      paths
      compiledPlan
      InferenceRequest
        { requestModelId = Text.pack representativeModelId,
          inputText = "service daemon request path",
          inputObjectRef = maybeInputObjectRef,
          requestUserId = Just requestUserIdValue,
          requestContextId = Just requestContextIdValue
        }
  maybeResult <- waitForPublishedResult paths compiledPlan requestIdValue
  case maybeResult of
    Nothing -> fail ("service daemon did not publish a result for " <> showRuntimeMode runtimeMode)
    Just resultValue -> do
      assert (resultModelId resultValue == Text.pack representativeModelId) "service daemon publishes the selected model id"
      assert (resultRuntimeMode resultValue == runtimeMode) "service daemon preserves the runtime mode in published results"
      -- Phase 6 Sprint 6.33 (2026-06-24): the service-runtime-loop HA test now
      -- TRUSTS the engine result and FAILS CLOSED. We assert the result reaches
      -- @status == "completed"@ (so @status=failed@ fails the loop — realness is
      -- the engine's job) and the per-family 'ResultFamily' contract, dispatched
      -- on the model descriptor so the check is substrate-agnostic: inline
      -- non-empty text for the text families, an 'infernix-demo-objects'
      -- object-ref for the artifact families. No dimension / byte-exactness
      -- assertions.
      assert
        (status resultValue == "completed")
        ( "service daemon completes the runtime-loop inference for "
            <> representativeModelId
            <> failurePayloadSuffix (payload resultValue)
        )
      assertResultFamilyContract (resultFamilyForDescriptor model) representativeModelId (payload resultValue)

validateDurableTopicFamilyRoundTrips :: Paths -> RuntimeMode -> String -> IO ()
validateDurableTopicFamilyRoundTrips paths runtimeMode representativeModelId = do
  runToken <- integrationRunToken
  let namespace = ConversationTopic.defaultDemoTopicNamespace
      runtimeText = runtimeModeId runtimeMode
      tokenText = Text.pack runToken
      userIdValue = Contracts.UserId ("integration-user-" <> runtimeText <> "-" <> tokenText)
      contextIdValue = Contracts.ContextId ("integration-context-" <> runtimeText <> "-" <> tokenText)
      contextIdText = Contracts.unContextId contextIdValue
      modelIdText = Text.pack representativeModelId
      contextTopic = ConversationTopic.contextsMetadataTopicName namespace userIdValue
      draftsTopic = ConversationTopic.draftsMetadataTopicName namespace userIdValue
      conversationTopic = ConversationTopic.conversationTopicName namespace userIdValue contextIdValue
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

integrationRunToken :: IO String
integrationRunToken = do
  now <- getPOSIXTime
  pure (show (floor (now * 1000000) :: Integer))

data DurablePromptContext = DurablePromptContext
  { durablePromptUserId :: Contracts.UserId,
    durablePromptContextId :: Contracts.ContextId,
    durablePromptModelId :: Text.Text,
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
        durablePromptModelId = modelIdText,
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

-- | Phase 6 Sprint 6.33 (2026-06-24) — family-aware, fail-closed assertion for
-- a durable-conversation inference result. The chaos / throughput / HA
-- scenarios drive a real prompt through the service loop; this TRUSTS the
-- engine result and asserts only the per-'ResultFamily' result surface, never
-- dimensions / byte-exactness (realness is the engine code's job). It fails
-- closed when @status /= "completed"@ (so @status=failed@ fails the scenario)
-- or when the expected family surface is missing/empty: a non-empty inline
-- result text for the text families (LLM, speech), and a non-empty
-- 'inferenceResultArtifacts' object reference (bucket + key present) for the
-- artifact families. Dispatch is purely on the model's 'ResultFamily', so the
-- check stays substrate-agnostic.
assertCompletedResultPayload :: ResultFamily -> Contracts.ConversationInferenceResultPayload -> String -> IO ()
assertCompletedResultPayload resultFamily resultPayload message = do
  assert
    (Contracts.inferenceResultStatus resultPayload == "completed")
    (message <> ": " <> show resultPayload)
  if resultFamilyIsArtifact resultFamily
    then assertArtifactSurface
    else assertTextSurface
  where
    familyLabel = Text.unpack (resultFamilyId resultFamily)
    assertArtifactSurface =
      case filter conversationArtifactRefNonEmpty (Contracts.inferenceResultArtifacts resultPayload) of
        _ : _ -> pure ()
        [] ->
          fail
            ( message
                <> ": artifact family "
                <> familyLabel
                <> " returned no non-empty object reference: "
                <> show resultPayload
            )
    assertTextSurface =
      case Contracts.inferenceResultInlineOutput resultPayload of
        Just text
          | not (Text.null (Text.strip text)) -> pure ()
        _ ->
          fail
            ( message
                <> ": text family "
                <> familyLabel
                <> " returned no non-empty inline result: "
                <> show resultPayload
            )

-- | A conversation result object reference is usable only when both the bucket
-- and key are non-empty.
conversationArtifactRefNonEmpty :: Contracts.ObjectRef -> Bool
conversationArtifactRefNonEmpty ref =
  not (Text.null (Contracts.objectBucket ref))
    && not (Text.null (Contracts.objectKey ref))

-- | Resolve the 'ResultFamily' of a substrate's representative model so the
-- chaos / throughput / HA scenarios can dispatch the fail-closed payload
-- assertion on it. Fails closed if the model is absent from the catalog.
resultFamilyForRepresentativeModel :: RuntimeMode -> String -> IO ResultFamily
resultFamilyForRepresentativeModel runtimeMode representativeModelId =
  case findModel runtimeMode (Text.pack representativeModelId) of
    Just descriptor -> pure (resultFamilyForDescriptor descriptor)
    Nothing ->
      fail ("model " <> representativeModelId <> " is not in the " <> showRuntimeMode runtimeMode <> " catalog")

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

-- Phase 6 Sprint 6.47 retained this case when the failure-injection tail was
-- deleted. It injects no failure at all: it measures fan-in batching, fan-out,
-- per-context ordering, and bounded p95 latency under concurrent load.
validateMultiUserDurablePromptThroughput :: Paths -> RuntimeMode -> String -> IO ()
validateMultiUserDurablePromptThroughput =
  validateMultiUserDurablePromptThroughputWith defaultThroughputMatrix

validateMultiUserDurablePromptThroughputWith :: ThroughputMatrix -> Paths -> RuntimeMode -> String -> IO ()
validateMultiUserDurablePromptThroughputWith matrix paths runtimeMode representativeModelId = do
  resultFamily <- resultFamilyForRepresentativeModel runtimeMode representativeModelId
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
      assertCompletedResultPayload resultFamily resultPayload "throughput prompt writes a completed result"
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

-- | Wave I (CUDA Linux cohort): the routed result-publish wait is a wall-clock
-- deadline rather than a fixed attempt count. The first GPU inference per engine
-- triggers a cold model bootstrap (Hugging Face -> MinIO -> engine model-cache):
-- on the cohort host an SDXL-Turbo snapshot alone fetches in ~14.5 min, so the
-- earlier 5-minute (3000 x 100 ms) ceiling — sized only for Poetry adapter
-- bootstrap plus the Pulsar two-hop handoff — timed out before real weights
-- landed. The deadline must sit above the engine's own
-- `modelBootstrapReadyWaitMaxSeconds` (3600 s) bootstrap envelope plus the MinIO
-- pull and on-GPU inference, so that a genuinely failed bootstrap surfaces as a
-- failed-status result this loop returns immediately (the caller then asserts on
-- the failure payload) rather than a client-side wait expiry. 70 minutes covers
-- the largest catalog repo (Wan2.1-T2V-1.3B `-Diffusers`) on a constrained link.
-- Warm/cached rows return in seconds.
waitForPublishedResult ::
  Paths ->
  ExecutionPlan.CompiledRuntimePlan ->
  Text.Text ->
  IO (Maybe InferenceResult)
waitForPublishedResult paths compiledPlan requestIdValue = do
  startTime <- getPOSIXTime
  go startTime
  where
    deadlineSeconds = 4200 :: Double
    go startTime = do
      maybeResult <- readPublishedInferenceResultMaybe paths compiledPlan requestIdValue
      case maybeResult of
        Just resultValue -> pure (Just resultValue)
        Nothing -> do
          nowTime <- getPOSIXTime
          if realToFrac (nowTime - startTime) >= deadlineSeconds
            then pure Nothing
            else do
              threadDelay 1000000
              go startTime

validateEdgePortConflictAndRediscovery :: Paths -> RuntimeMode -> IO ()
validateEdgePortConflictAndRediscovery paths runtimeMode = do
  cleanupRuntimeState paths runtimeMode
  busyState <-
    bracket (openBusyTcpPort 9090) closeBusyTcpPortFixture $ \_busyFixture -> do
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

data BusyTcpPortFixture
  = OwnedBusyTcpPort Socket
  | PreexistingBusyTcpPort

closeBusyTcpPortFixture :: BusyTcpPortFixture -> IO ()
closeBusyTcpPortFixture fixture =
  case fixture of
    OwnedBusyTcpPort busySocket -> close busySocket
    PreexistingBusyTcpPort -> pure ()

openBusyTcpPort :: Int -> IO BusyTcpPortFixture
openBusyTcpPort port = go (300 :: Int) Nothing
  where
    go remainingAttempts maybeLastError
      | remainingAttempts <= 0 =
          ioError
            ( userError
                ( "timed out waiting to bind busy edge-port fixture on 127.0.0.1:"
                    <> show port
                    <> maybe "" (("\nlast bind error: " <>) . displayException) maybeLastError
                )
            )
      | otherwise = do
          result <- try (openBusyTcpPortOnce port) :: IO (Either IOException Socket)
          case result of
            Right busySocket -> pure (OwnedBusyTcpPort busySocket)
            Left err
              | isAlreadyInUseError err -> pure PreexistingBusyTcpPort
              | otherwise -> do
                  threadDelay 100000
                  go (remainingAttempts - 1) (Just err)

openBusyTcpPortOnce :: Int -> IO Socket
openBusyTcpPortOnce port =
  bracketOnError
    (socket AF_INET Stream defaultProtocol)
    close
    ( \busySocket -> do
        setSocketOption busySocket ReuseAddr 1
        bind busySocket (SockAddrInet (fromIntegral port) (tupleToHostAddress (127, 0, 0, 1)))
        listen busySocket 1
        pure busySocket
    )

validateDemoUiDisabled :: Paths -> RuntimeMode -> IO ()
validateDemoUiDisabled paths runtimeMode =
  ( do
      cleanupRuntimeState paths runtimeMode
      materializeGeneratedSubstrate runtimeMode False
      withClusterLifecycle runtimeMode $ do
        state <- maybe (fail "cluster state was not available after demo-disabled cluster up") pure =<< loadClusterState paths
        assert (clusterPresent state) "cluster up records cluster presence when demo_ui is disabled"
        coordinatorReplicas <- deploymentSpecReplicas state "infernix-coordinator"
        assert (coordinatorReplicas >= 1) "production demo_ui=false topology keeps the coordinator deployment"
        when (runtimeMode /= AppleSilicon) $ do
          engineReplicas <- deploymentSpecReplicas state "infernix-engine"
          assert (engineReplicas >= 1) "production demo_ui=false Linux topology keeps the engine deployment"
        assert (not (any ((== "/") . path) (routes state))) "route inventory omits the browser root when demo_ui is disabled"
        assert (not (any ((== "/api") . path) (routes state))) "route inventory omits the demo API when demo_ui is disabled"
        let baseUrl = routeBaseUrl paths state
        disabledHomeResult <- try (httpGet (baseUrl <> "/")) :: IO (Either IOError String)
        disabledPublicationResult <- try (httpGet (baseUrl <> "/api/publication")) :: IO (Either IOError String)
        harborResponse <- httpGet (baseUrl <> "/harbor")
        pulsarAdminResponse <- httpGet (baseUrl <> "/pulsar/admin/admin/v2/clusters")
        (pulsarHttpStatus, _) <- httpGetWithStatus (baseUrl <> "/pulsar/ws/v2/producer/public/default/demo")
        assert (either (const True) (const False) disabledHomeResult) "the browser root is absent when demo_ui is disabled"
        assert (either (const True) (const False) disabledPublicationResult) "the demo API is absent when demo_ui is disabled"
        assert ("Harbor" `isInfixOf` harborResponse) "harbor remains published when demo_ui is disabled"
        assert
          (not (any ((== "/minio/s3") . path) (routes state)))
          "Phase 3 Sprint 3.13: the /minio/s3 external gateway route is removed from the published route inventory"
        assert
          ("[\"infernix-infernix-pulsar\"]" `isInfixOf` compact pulsarAdminResponse)
          "pulsar admin remains published when demo_ui is disabled"
        assert
          (pulsarHttpStatus == 405)
          "pulsar websocket route remains published when demo_ui is disabled"
  )
    `finallyPreservingPrimary` materializeGeneratedSubstrate runtimeMode True

resolveInfernixExecutable :: IO FilePath
resolveInfernixExecutable = getExecutablePath

trim :: String -> String
trim =
  dropWhile (`elem` [' ', '\n', '\r', '\t'])
    . reverse
    . dropWhile (`elem` [' ', '\n', '\r', '\t'])
    . reverse

cleanupRuntimeState :: Paths -> RuntimeMode -> IO ()
cleanupRuntimeState = cleanupHarnessRuntimeState

captureInfernixOutput :: [String] -> IO String
captureInfernixOutput args = do
  infernixExecutable <- resolveInfernixExecutable
  (exitCode, stdoutOutput, stderrOutput) <-
    readProcessWithExitCode
      infernixExecutable
      (integrationCliSelfExecMarker : args)
      ""
  assert (exitCode == ExitSuccess) ("infernix command succeeded: " <> stderrOutput)
  pure stdoutOutput

httpGet :: String -> IO String
httpGet url =
  readProcessWithTransientCurlRetry ["-fsS", url]

waitForRoutedDemoConfig :: Paths -> ClusterState -> IO String
waitForRoutedDemoConfig paths state = go (120 :: Int)
  where
    url = routeBaseUrl paths state <> "/api/demo-config"
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail ("timed out waiting for routed demo config endpoint " <> url)
      | otherwise = do
          result <- try (httpGet url) :: IO (Either SomeException String)
          case result of
            Right payload
              | "\"demo_ui\":true" `isInfixOf` compact payload -> pure payload
              | otherwise -> retry
            Left _ -> retry
      where
        retry = do
          threadDelay 1000000
          go (remainingAttempts - 1)

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

requireCompiledRuntimePlanFile :: FilePath -> IO ExecutionPlan.CompiledRuntimePlan
requireCompiledRuntimePlanFile configPath = do
  compiledPlanResult <- decodeCompiledRuntimePlanFile configPath
  case compiledPlanResult of
    Right compiledPlan -> pure compiledPlan
    Left errors ->
      fail
        ( "unable to compile generated execution plan "
            <> configPath
            <> ": "
            <> show errors
        )

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

usesDetachedRetainedSnapshot :: Paths -> RuntimeMode -> Bool
usesDetachedRetainedSnapshot paths runtimeMode =
  case runtimeMode of
    AppleSilicon -> True
    _ -> Config.controlPlaneContext paths == Config.HostNative

-- Sprint 2.14 acceptance for the Apple/non-bind lifecycle. A unique canary is
-- written only to a live non-Patroni MinIO claim. While Kind is live it must not
-- appear in the detached host mirror. Teardown then freezes and commits that
-- claim before deleting Kind, after which its WriterQuiesced scrub removes only
-- rebuildable Harbor storage from the detached copy. Before recreate, the test
-- turns that committed snapshot into a crash residue: the last committed tree
-- is under @.previous@ and an unmarked partial @.incoming@ also exists. The
-- first recreate is killed after Kind exists and the exact replay intent moves
-- to ClusterActivating. A second recreate must resume that intent, recover the
-- committed tree before claim preparation, replay the canary, remove both
-- residues, and provision a fresh Harbor registry bucket.
validateDetachedRetainedSnapshotReplay :: Paths -> RuntimeMode -> IO ()
validateDetachedRetainedSnapshotReplay paths runtimeMode = do
  state <-
    maybe
      (fail "cluster state was not available before retained snapshot validation")
      pure
      =<< loadClusterState paths
  retainedClaim <-
    maybe
      (fail "the cluster state did not contain a non-Patroni MinIO data claim")
      pure
      (find isMinioDataClaim (claims state))
  now <- getPOSIXTime
  let token = show (round (now * 1000000) :: Integer)
      podName = "infernix-minio-" <> show (ordinal retainedClaim)
      canaryName = "phase2-retained-" <> token <> ".txt"
      canaryPayload = "writer-frozen-retained-" <> token
      retainedRuntimeRoot =
        kindRoot paths </> showRuntimeMode runtimeMode
      previousSnapshotRoot =
        retainedRuntimeRoot <> ".previous"
      incomingSnapshotRoot =
        retainedRuntimeRoot <> ".incoming"
      retainedClaimRoot =
        retainedRuntimeRoot
          </> Text.unpack (namespace retainedClaim)
          </> Text.unpack (release retainedClaim)
          </> Text.unpack (workload retainedClaim)
          </> show (ordinal retainedClaim)
          </> Text.unpack (claim retainedClaim)
      retainedCanaryPath = retainedClaimRoot </> "ha-smoke" </> canaryName
      retainedHarborRoot = retainedClaimRoot </> "harbor-registry"
  waitForPodReady state "platform" podName
  mountPath <- podMountPathForVolume state "platform" podName "data"
  assert (not (null mountPath)) "the selected MinIO claim has a live pod mount"
  let liveCanaryPath = mountPath </> "ha-smoke" </> canaryName
      liveHarborRoot = mountPath </> "harbor-registry"
  runKubectl
    state
    [ "-n",
      "platform",
      "exec",
      podName,
      "--",
      "sh",
      "-c",
      "mkdir -p \"$1\" && printf '%s' \"$2\" > \"$3\"",
      "infernix-retained-snapshot-canary",
      mountPath </> "ha-smoke",
      canaryPayload,
      liveCanaryPath
    ]
  liveCanaryContents <-
    trim
      <$> kubectlOutputForState
        state
        ["-n", "platform", "exec", podName, "--", "cat", liveCanaryPath]
  liveHarborPresent <- remotePathExists state podName liveHarborRoot
  detachedCanaryPresentWhileLive <- doesFileExist retainedCanaryPath
  detachedHarborPresentWhileLive <- doesDirectoryExist retainedHarborRoot
  assert
    ( liveCanaryContents == canaryPayload
        && liveHarborPresent
        && not detachedCanaryPresentWhileLive
        && not detachedHarborPresentWhileLive
    )
    "the live MinIO writer contains the canary and Harbor bucket while its detached host mirror remains untouched"

  clusterDownHarness (Just runtimeMode)
  downState <- loadClusterState paths
  retainedCanaryPresent <- doesFileExist retainedCanaryPath
  retainedCanaryContents <-
    if retainedCanaryPresent
      then trim <$> readFile retainedCanaryPath
      else pure ""
  retainedHarborPresent <- doesDirectoryExist retainedHarborRoot
  assert
    ( maybe False (not . clusterPresent) downState
        && retainedCanaryContents == canaryPayload
        && not retainedHarborPresent
    )
    "post-delete detached snapshot retains non-Patroni data and scrubs rebuildable Harbor storage under WriterQuiesced"

  renameDirectory retainedRuntimeRoot previousSnapshotRoot
  createDirectoryIfMissing True incomingSnapshotRoot
  writeFile
    (incomingSnapshotRoot </> "partial-copy")
    "unmarked incomplete snapshot must not be promoted\n"
  interruptBringUpDuringRetainedReplay paths runtimeMode
  clusterUpHarness (Just runtimeMode)
  reboundState <-
    maybe
      (fail "cluster state was not available after retained snapshot replay")
      pure
      =<< loadClusterState paths
  waitForPodReady reboundState "platform" podName
  reboundMountPath <- podMountPathForVolume reboundState "platform" podName "data"
  assert (not (null reboundMountPath)) "the replayed MinIO claim has a live pod mount"
  reboundCanaryContents <-
    trim
      <$> kubectlOutputForState
        reboundState
        [ "-n",
          "platform",
          "exec",
          podName,
          "--",
          "cat",
          reboundMountPath </> "ha-smoke" </> canaryName
        ]
  reboundHarborPresent <-
    remotePathExists
      reboundState
      podName
      (reboundMountPath </> "harbor-registry")
  previousResiduePresent <- doesDirectoryExist previousSnapshotRoot
  incomingResiduePresent <- doesDirectoryExist incomingSnapshotRoot
  assert
    ( reboundCanaryContents == canaryPayload
        && reboundHarborPresent
        && not previousResiduePresent
        && not incomingResiduePresent
    )
    "cluster recreate recovers the last committed snapshot before claim preparation, removes partial swap residue, replays the canary, and provisions fresh Harbor storage"
  where
    isMinioDataClaim persistentClaim =
      namespace persistentClaim == "platform"
        && workload persistentClaim == "minio"
        && claim persistentClaim == "data"

data RetainedReplayBringUpObservation
  = RetainedReplayActivated
  | RetainedReplayBringUpExited ProcessStatus
  | RetainedReplayObservationTimedOut

interruptBringUpDuringRetainedReplay :: Paths -> RuntimeMode -> IO ()
interruptBringUpDuringRetainedReplay paths runtimeMode = do
  baselineActivities <- boundedCommandActivityLeaseNames paths
  bracketPreservingPrimary
    ( forkProcessWithUnmask
        (\unmask -> unmask (clusterUpHarness (Just runtimeMode)))
    )
    stopInterruptedBringUp
    ( \bringUpPid -> do
        observation <-
          waitForRetainedReplayActivation
            paths
            baselineActivities
            bringUpPid
            (7200 :: Int)
        case observation of
          RetainedReplayActivated -> do
            signalProcess sigKILL bringUpPid
            processStatus <-
              maybe
                (fail "interrupted retained replay child did not produce an exit status")
                pure
                =<< getProcessStatus True False bringUpPid
            assert
              (retainedReplayBringUpWasKilled processStatus)
              "the first recreated cluster bring-up is killed while retained replay intent is active"
            waitForInterruptedBringUpCommandsToQuiesce paths 1000
          RetainedReplayBringUpExited processStatus ->
            fail
              ( "the first recreated cluster bring-up exited before retained replay became active: "
                  <> show processStatus
              )
          RetainedReplayObservationTimedOut ->
            fail
              "timed out waiting for the first recreated cluster bring-up to publish active retained replay intent"
    )

retainedReplayBringUpWasKilled :: ProcessStatus -> Bool
retainedReplayBringUpWasKilled processStatus =
  case processStatus of
    Terminated signal _ -> signal == sigKILL
    _ -> False

waitForRetainedReplayActivation ::
  Paths ->
  Set.Set FilePath ->
  ProcessID ->
  Int ->
  IO RetainedReplayBringUpObservation
waitForRetainedReplayActivation paths baselineActivities bringUpPid remainingAttempts
  | remainingAttempts <= 0 = pure RetainedReplayObservationTimedOut
  | otherwise = do
      maybeState <- loadClusterState paths
      replayCopyActivityPublished <-
        case maybeState of
          Just state
            | clusterPresent state,
              retainedReplayPending state,
              maybe
                False
                ( ("copying retained Kind runtime data into " `isPrefixOf`)
                    . lifecyclePhaseDetail
                )
                (lifecyclePhaseOf state) ->
                do
                  currentActivities <- boundedCommandActivityLeaseNames paths
                  pure
                    ( not
                        ( Set.null
                            (currentActivities `Set.difference` baselineActivities)
                        )
                    )
          _ -> pure False
      if replayCopyActivityPublished
        then pure RetainedReplayActivated
        else do
          maybeStatus <- getProcessStatus False False bringUpPid
          case maybeStatus of
            Just processStatus ->
              pure (RetainedReplayBringUpExited processStatus)
            Nothing -> do
              threadDelay 50000
              waitForRetainedReplayActivation
                paths
                baselineActivities
                bringUpPid
                (remainingAttempts - 1)

boundedCommandActivityLeaseNames :: Paths -> IO (Set.Set FilePath)
boundedCommandActivityLeaseNames paths = do
  let activityRoot = runtimeRoot paths </> "bounded-command-activity"
  rootExists <- doesDirectoryExist activityRoot
  if rootExists
    then
      Set.fromList
        . filter (".lease.json" `isSuffixOf`)
        <$> listDirectory activityRoot
    else pure Set.empty

stopInterruptedBringUp :: ProcessID -> IO ()
stopInterruptedBringUp bringUpPid = do
  maybeStatusResult <-
    try @IOException (getProcessStatus False False bringUpPid)
  case maybeStatusResult of
    Left _ -> pure ()
    Right (Just _) -> pure ()
    Right Nothing -> do
      _ <- try @IOException (signalProcess sigKILL bringUpPid)
      _ <- try @IOException (getProcessStatus True False bringUpPid)
      pure ()

waitForInterruptedBringUpCommandsToQuiesce :: Paths -> Int -> IO ()
waitForInterruptedBringUpCommandsToQuiesce paths remainingAttempts
  | remainingAttempts <= 0 =
      fail
        "bounded commands from the killed retained replay bring-up did not become quiescent"
  | otherwise = do
      reservationProcessGroup <- fromIntegral <$> getProcessGroupID
      quiescenceResult <-
        try @IOException
          ( requireBoundedCommandActivitiesQuiescent
              paths
              reservationProcessGroup
          )
      case quiescenceResult of
        Right _ -> pure ()
        Left _ -> do
          threadDelay 10000
          waitForInterruptedBringUpCommandsToQuiesce
            paths
            (remainingAttempts - 1)

remotePathExists :: ClusterState -> String -> FilePath -> IO Bool
remotePathExists state podName pathValue =
  (== "present")
    . trim
    <$> kubectlOutputForState
      state
      [ "-n",
        "platform",
        "exec",
        podName,
        "--",
        "sh",
        "-c",
        "if [ -e \"$1\" ]; then printf present; else printf absent; fi",
        "infernix-remote-path-exists",
        pathValue
      ]

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

-- | Phase 3 Sprint 3.16: the positive proof that the single-node topology
-- schedules.
--
-- The retired case scaled `infernix-engine` past the node count and required the
-- surplus replica to sit `Pending` with a `FailedScheduling` event naming pod
-- anti-affinity. That asserted a constraint this repository no longer wants: one
-- engine process per machine is a correctness rule about KV caches and admission,
-- not a placement preference the scheduler is asked to enforce, and expressing it
-- as anti-affinity produced a `Pending` pod instead of preventing a second
-- process.
--
-- This replacement is deliberately the *inverse* assertion, and it is weaker in
-- one specific way that is recorded rather than glossed: it proves nothing about
-- what happens if an operator raises `engine.replicaCount` themselves. It proves
-- only that the deployed topology has no unsatisfiable placement constraint left
-- in it — which is exactly the residue a partial collapse would leave behind.
validateNoPendingWorkloadReplicas :: ClusterState -> IO ()
validateNoPendingWorkloadReplicas state = do
  podLines <-
    filter (not . null)
      . lines
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "pods",
          "--no-headers",
          "-o",
          "custom-columns=NAME:.metadata.name,PHASE:.status.phase"
        ]
  let pendingPods =
        [ podName
        | podLine <- podLines,
          podName : phaseValue : _ <- [words podLine],
          phaseValue == "Pending"
        ]
  assert
    (null pendingPods)
    ( "the collapsed single-node topology schedules every workload; these pods are Pending: "
        <> unwords pendingPods
    )

data EnginePodPlacement = EnginePodPlacement
  { enginePodPlacementPodName :: String,
    enginePodPlacementNodeName :: String,
    enginePodPlacementPhase :: String
  }
  deriving (Eq, Show)

validateLinuxEnginePoolPlacement :: ClusterState -> RuntimeMode -> ExecutionPlan.CompiledRuntimePlan -> IO ()
validateLinuxEnginePoolPlacement state runtimeMode compiledPlan = do
  runKubectl state ["-n", "platform", "rollout", "status", "deployment/infernix-engine", "--timeout=900s"]
  podPlacementLines <-
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
          "jsonpath={range .items[*]}{.metadata.name}|{.spec.nodeName}|{.status.phase}{\"\\n\"}{end}"
        ]
  let placements = mapMaybe parseEnginePodPlacement podPlacementLines
      runningPlacements = filter ((== "Running") . enginePodPlacementPhase) placements
      compiledEngineDaemons = ExecutionPlan.compiledPlanEngineDaemons compiledPlan
      compiledRoutes =
        concatMap
          (NonEmpty.toList . ExecutionPlan.compiledPlacementRoutes)
          (ExecutionPlan.compiledRuntimePlanPlacements compiledPlan)
      memberIds = mapMaybe ExecutionPlan.compiledDaemonMemberId compiledEngineDaemons
      engineTopics = concatMap ExecutionPlan.compiledDaemonRequestTopics compiledEngineDaemons
      expectedTopics = map ExecutionPlan.engineRouteTopic compiledRoutes
      routingSurface =
        Text.unpack
          ( Text.unwords
              ( memberIds
                  <> map ExecutionPlan.engineRoutePoolId compiledRoutes
                  <> map ExecutionPlan.engineRouteMemberId compiledRoutes
                  <> engineTopics
              )
          )
  assert (runtimeMode == LinuxCpu) "linux engine placement validation runs on the linux-cpu cohort"
  -- Phase 3 Sprint 3.16 follow-on: inverted, not retired. The retired form
  -- required at least two running engine pods on at least two distinct worker
  -- nodes, which asserted the replicated topology this sprint deletes — and it
  -- asserted it as a *floor*, so the collapse could not satisfy it at all. The
  -- companion line said the member id held "independent of pod count", which is
  -- the doctrine violation written down as an invariant: two engine pods
  -- sharing one member id are two KV caches and two copies of every loaded
  -- weight, each admitting work against the whole machine's observed capacity.
  --
  -- One engine process per machine is the rule, so the exact count is the
  -- assertion. The node-spread assertion is deleted rather than inverted: it
  -- expressed the anti-affinity constraint, and with one pod there is nothing
  -- to spread.
  assert
    (length runningPlacements == 1)
    ( "linux-cpu runs exactly one engine pod, one engine process per machine; running pods: "
        <> show (map enginePodPlacementPodName runningPlacements)
    )
  assert (memberIds == ["linux-cpu-engine"]) "linux-cpu compiles exactly one engine member id"
  assert
    (all ((== "cluster-pod") . ExecutionPlan.compiledDaemonLocation) compiledEngineDaemons)
    "linux engine members are cluster-pod members"
  assert
    (all (`elem` engineTopics) expectedTopics)
    "linux engine daemons include every available compiled placement route"
  forM_ runningPlacements $ \placement -> do
    assert
      (enginePodPlacementPodName placement `notElemString` routingSurface)
      "linux routing ids do not encode live engine pod names"
    assert
      (enginePodPlacementNodeName placement `notElemString` routingSurface)
      "linux routing ids do not encode Kubernetes node names"

parseEnginePodPlacement :: String -> Maybe EnginePodPlacement
parseEnginePodPlacement lineValue =
  case splitPipes lineValue of
    [podNameValue, nodeNameValue, phaseValue]
      | not (null podNameValue) && not (null nodeNameValue) ->
          Just
            EnginePodPlacement
              { enginePodPlacementPodName = podNameValue,
                enginePodPlacementNodeName = nodeNameValue,
                enginePodPlacementPhase = phaseValue
              }
    _ -> Nothing

splitPipes :: String -> [String]
splitPipes value =
  case break (== '|') value of
    (segment, []) -> [segment]
    (segment, _ : rest) -> segment : splitPipes rest

-- | Phase 7 Sprint 7.24 Wave J: prove the Shared subscription's
-- broker-native permit/backlog behavior with one busy logical Apple
-- member and one free logical Apple member. A test-owned subscription keeps
-- the check isolated from the live service consumer on the compiled route.
validateAppleSharedSubscriptionBackpressure :: Paths -> ExecutionPlan.CompiledRuntimePlan -> IO ()
validateAppleSharedSubscriptionBackpressure paths compiledPlan = do
  (modelIdValue, sharedTopic, subscriptionName) <- isolatedSharedBackpressureFixture AppleSilicon compiledPlan
  validateSharedSubscriptionBackpressure paths AppleSilicon compiledPlan modelIdValue sharedTopic subscriptionName "apple"

validateLinuxSharedSubscriptionBackpressure :: Paths -> RuntimeMode -> ExecutionPlan.CompiledRuntimePlan -> IO ()
validateLinuxSharedSubscriptionBackpressure paths runtimeMode compiledPlan = do
  (modelIdValue, sharedTopic, subscriptionName) <- isolatedSharedBackpressureFixture runtimeMode compiledPlan
  validateSharedSubscriptionBackpressure paths runtimeMode compiledPlan modelIdValue sharedTopic subscriptionName "linux"

validateSharedSubscriptionBackpressure ::
  Paths ->
  RuntimeMode ->
  ExecutionPlan.CompiledRuntimePlan ->
  Text.Text ->
  Text.Text ->
  String ->
  String ->
  IO ()
validateSharedSubscriptionBackpressure paths runtimeMode compiledPlan modelIdValue sharedTopic subscriptionName cohortLabel = do
  transport <-
    maybe
      (fail ("Pulsar transport was unavailable for " <> cohortLabel <> " shared backpressure validation"))
      pure
      =<< discoverPulsarTransport paths runtimeMode Nothing
  let websocketBase = pulsarWebSocketBase transport
      busyConsumerName = serviceConsumerName subscriptionName ConsumerShared "integration-busy"
      freeConsumerName = serviceConsumerName subscriptionName ConsumerShared "integration-free"
  busyConsumerPath <- integrationSharedConsumerSocketPath websocketBase sharedTopic subscriptionName busyConsumerName
  freeConsumerPath <- integrationSharedConsumerSocketPath websocketBase sharedTopic subscriptionName freeConsumerName
  withIntegrationPulsarClient websocketBase busyConsumerPath $ \busyConnection -> do
    busyRequestId <-
      publishInferenceRequest
        paths
        compiledPlan
        InferenceRequest
          { requestModelId = modelIdValue,
            inputText = Text.pack ("shared " <> cohortLabel <> " engine busy logical member"),
            inputObjectRef = Nothing,
            requestUserId = Nothing,
            requestContextId = Nothing
          }
    (busyMessageId, observedBusyRequestId) <-
      receiveSharedInferenceRequest busyConnection "busy shared-subscription consumer"
    assert
      (observedBusyRequestId == busyRequestId)
      "busy shared-subscription consumer receives the first published request"
    withIntegrationPulsarClient websocketBase freeConsumerPath $ \freeConnection -> do
      assertPulsarSubscriptionConsumerCount transport sharedTopic subscriptionName 2
      freeRequestId <-
        publishInferenceRequest
          paths
          compiledPlan
          InferenceRequest
            { requestModelId = modelIdValue,
              inputText = Text.pack ("shared " <> cohortLabel <> " engine free logical member"),
              inputObjectRef = Nothing,
              requestUserId = Nothing,
              requestContextId = Nothing
            }
      (freeMessageId, observedFreeRequestId) <-
        receiveSharedInferenceRequest freeConnection "free shared-subscription consumer"
      assert
        (observedFreeRequestId == freeRequestId)
        "free shared-subscription consumer receives the second request while the first consumer is busy"
      ackIntegrationPulsarMessage freeConnection freeMessageId
      ackIntegrationPulsarMessage busyConnection busyMessageId

isolatedSharedBackpressureFixture ::
  RuntimeMode ->
  ExecutionPlan.CompiledRuntimePlan ->
  IO (Text.Text, Text.Text, String)
isolatedSharedBackpressureFixture runtimeMode compiledPlan = do
  (_, modelIdValue, sharedTopic) <- requireCompiledSharedRoute Nothing compiledPlan
  uniqueSuffix <- integrationRunToken
  pure
    ( modelIdValue,
      sharedTopic,
      "infernix-integration-shared-backpressure-"
        <> Text.unpack (runtimeModeId runtimeMode)
        <> "-"
        <> uniqueSuffix
    )

requireCompiledSharedRoute ::
  Maybe Text.Text ->
  ExecutionPlan.CompiledRuntimePlan ->
  IO (Text.Text, Text.Text, Text.Text)
requireCompiledSharedRoute maybePreferredModelId compiledPlan = do
  placement <-
    case maybePreferredModelId >>= (`ExecutionPlan.lookupCompiledPlacement` compiledPlan) of
      Just preferredPlacement -> pure preferredPlacement
      Nothing ->
        case ExecutionPlan.compiledRuntimePlanPlacements compiledPlan of
          firstPlacement : _ -> pure firstPlacement
          [] -> fail "compiled execution plan does not contain an available engine placement"
  let route = NonEmpty.head (ExecutionPlan.compiledPlacementRoutes placement)
      memberIdValue = ExecutionPlan.engineRouteMemberId route
      modelIdValue = ExecutionPlan.compiledPlacementId placement
      topicValue = ExecutionPlan.engineRouteTopic route
  unless (ExecutionPlan.engineRouteSubscriptionType route == ConsumerShared) $
    fail ("compiled engine route is not Shared: " <> Text.unpack topicValue)
  daemon <-
    maybe
      (fail ("compiled execution plan does not contain engine daemon " <> Text.unpack memberIdValue))
      pure
      (ExecutionPlan.lookupCompiledEngineDaemon memberIdValue compiledPlan)
  unless (ExecutionPlan.compiledDaemonConsumerSubscriptionType daemon == Just ConsumerShared) $
    fail ("compiled engine daemon is not a Shared consumer for " <> Text.unpack memberIdValue)
  unless (topicValue `elem` ExecutionPlan.compiledDaemonRequestTopics daemon) $
    fail ("compiled engine daemon does not consume its placement route " <> Text.unpack topicValue)
  pure (memberIdValue, modelIdValue, topicValue)

integrationSharedConsumerSocketPath :: PulsarWebSocketBase -> Text.Text -> String -> String -> IO String
integrationSharedConsumerSocketPath websocketBase topicValue subscriptionName consumerName = do
  topicPath <- integrationPersistentTopicPath topicValue
  pure
    ( integrationSocketPath
        websocketBase
        ("consumer/" <> topicPath <> "/" <> subscriptionName)
        [ ("subscriptionType", "Shared"),
          ("subscriptionInitialPosition", "Latest"),
          ("receiverQueueSize", "1"),
          ("consumerName", consumerName)
        ]
    )

integrationPersistentTopicPath :: Text.Text -> IO String
integrationPersistentTopicPath topicValue =
  case Text.stripPrefix "persistent://" topicValue of
    Just topicPath | not (Text.null topicPath) -> pure ("persistent/" <> Text.unpack topicPath)
    _ -> fail ("unsupported Pulsar topic name for WebSocket consumer: " <> Text.unpack topicValue)

integrationSocketPath :: PulsarWebSocketBase -> String -> [(String, String)] -> String
integrationSocketPath websocketBase relativePath queryParameters =
  case queryParameters of
    [] -> path
    _ -> path <> "?" <> intercalate "&" [key <> "=" <> value | (key, value) <- queryParameters]
  where
    path = joinIntegrationSocketPath (pulsarWsPathPrefix websocketBase) relativePath

joinIntegrationSocketPath :: String -> String -> String
joinIntegrationSocketPath basePath relativePath =
  case trimTrailingSlash basePath of
    "" -> "/" <> normalizedRelative
    normalizedBase -> normalizedBase <> "/" <> normalizedRelative
  where
    normalizedRelative = dropWhile (== '/') relativePath

trimTrailingSlash :: String -> String
trimTrailingSlash =
  reverse . dropWhile (== '/') . reverse

withIntegrationPulsarClient :: PulsarWebSocketBase -> String -> (WebSockets.Connection -> IO a) -> IO a
withIntegrationPulsarClient websocketBase socketPath action =
  WebSockets.runClient (pulsarWsHost websocketBase) (pulsarWsPort websocketBase) socketPath $ \connection ->
    WebSockets.withPingThread connection 15 (pure ()) (action connection)

receiveSharedInferenceRequest :: WebSockets.Connection -> String -> IO (Text.Text, Text.Text)
receiveSharedInferenceRequest connection label = do
  maybeRawFrame <- timeout (10 * 1000000) (WebSockets.receiveData connection :: IO Text.Text)
  rawFrame <-
    maybe
      (fail ("timed out waiting for Pulsar message on " <> label))
      pure
      maybeRawFrame
  envelope <-
    case Aeson.eitherDecodeStrict' (TextEncoding.encodeUtf8 rawFrame) of
      Right decodedEnvelope -> pure decodedEnvelope
      Left err -> fail ("failed to decode Pulsar message envelope on " <> label <> ": " <> err)
  payloadBytes <-
    case Base64.decode (TextEncoding.encodeUtf8 (integrationEnvelopePayload envelope)) of
      Right decodedPayload -> pure decodedPayload
      Left err -> fail ("failed to decode Pulsar message payload on " <> label <> ": " <> err)
  case rawTopicInferenceRequestIds
    [ RawTopicMessage
        { rawTopicMessageId = integrationEnvelopeMessageId envelope,
          rawTopicMessageKey = Nothing,
          rawTopicMessagePayload = payloadBytes
        }
    ] of
    requestIdValue : _ -> pure (integrationEnvelopeMessageId envelope, requestIdValue)
    [] -> fail ("failed to decode inference request payload on " <> label)

ackIntegrationPulsarMessage :: WebSockets.Connection -> Text.Text -> IO ()
ackIntegrationPulsarMessage connection messageIdValue =
  WebSockets.sendTextData
    connection
    ( TextEncoding.decodeUtf8
        ( LazyByteString.toStrict
            (Aeson.encode (Aeson.object ["messageId" .= messageIdValue]))
        )
    )

assertPulsarSubscriptionConsumerCount :: PulsarTransport -> Text.Text -> String -> Int -> IO ()
assertPulsarSubscriptionConsumerCount transport topicValue subscriptionName expectedCount = go (120 :: Int) Nothing
  where
    go remainingAttempts maybeLastObservation
      | remainingAttempts <= 0 =
          fail
            ( "timed out waiting for Pulsar subscription "
                <> subscriptionName
                <> " to report at least "
                <> show expectedCount
                <> " consumers"
                <> maybe "" ("\nlast observation: " <>) maybeLastObservation
            )
      | otherwise = do
          statsResult <- try (readPulsarTopicStatsPayload transport topicValue) :: IO (Either SomeException LazyByteString.ByteString)
          case statsResult of
            Right statsPayload ->
              case pulsarSubscriptionConsumerCount subscriptionName statsPayload of
                Just consumerCount
                  | consumerCount >= expectedCount -> pure ()
                  | otherwise -> retry (Just ("observed " <> show consumerCount <> " consumers"))
                Nothing -> retry (Just "Pulsar stats payload did not contain the expected subscription consumer list")
            Left err -> retry (Just (displayException err))
      where
        retry observation = do
          threadDelay 1000000
          go (remainingAttempts - 1) observation

readPulsarTopicStatsPayload :: PulsarTransport -> Text.Text -> IO LazyByteString.ByteString
readPulsarTopicStatsPayload transport topicValue = do
  statsUrl <- pulsarTopicStatsUrl transport topicValue
  LazyByteStringChar8.pack <$> readProcessWithTransientCurlRetry ["-fsS", statsUrl]

pulsarTopicStatsUrl :: PulsarTransport -> Text.Text -> IO String
pulsarTopicStatsUrl transport topicValue = do
  adminBaseUrl <-
    maybe
      (fail "Pulsar admin base URL is not available for subscription stats lookup")
      pure
      (pulsarAdminBaseUrl transport)
  case Text.stripPrefix "persistent://" topicValue of
    Just topicPath ->
      pure (trimTrailingSlash adminBaseUrl <> "/persistent/" <> Text.unpack topicPath <> "/stats")
    Nothing -> fail ("unsupported Pulsar topic name for stats lookup: " <> Text.unpack topicValue)

pulsarSubscriptionConsumerCount :: String -> LazyByteString.ByteString -> Maybe Int
pulsarSubscriptionConsumerCount subscriptionName statsPayload = do
  Aeson.Object root <- Aeson.decode statsPayload :: Maybe Aeson.Value
  Aeson.Object subscriptionsObject <- AesonKeyMap.lookup (AesonKey.fromString "subscriptions") root
  Aeson.Object subscriptionObject <- AesonKeyMap.lookup (AesonKey.fromString subscriptionName) subscriptionsObject
  Aeson.Array consumersArray <- AesonKeyMap.lookup (AesonKey.fromString "consumers") subscriptionObject
  pure (length consumersArray)

-- | The argument vector is passed as given. The self-exec marker belongs to a
-- command this suite runs against its own image; the host inference daemon is
-- the installed operator CLI, which has no such marker and answers the marker
-- with its usage text rather than with a daemon.
withLoggedServiceDaemon :: Paths -> FilePath -> [String] -> FilePath -> (ProcessHandle -> FilePath -> IO a) -> IO a
withLoggedServiceDaemon paths infernixExecutable args logPath action =
  withLoggedProcess
    logPath
    ( pure
        (proc infernixExecutable args)
          { cwd = Just (repoRoot paths)
          }
    )
    (`action` logPath)

withLoggedProcess :: FilePath -> IO CreateProcess -> (ProcessHandle -> IO a) -> IO a
withLoggedProcess logPath loadProcess action = do
  createDirectoryIfMissing True (takeDirectoryPortable logPath)
  bracketPreservingPrimary
    (openFile logPath WriteMode)
    hClose
    ( \logHandle -> do
        hSetBuffering logHandle LineBuffering
        processSpec <- loadProcess
        bracketPreservingPrimary
          ( do
              (_, _, _, processHandle) <-
                createProcess
                  processSpec
                    { std_out = UseHandle logHandle,
                      std_err = UseHandle logHandle
                    }
              pure processHandle
          )
          stopChildProcess
          action
    )

stopChildProcess :: ProcessHandle -> IO ()
stopChildProcess processHandle =
  runCleanupsPreservingFailures
    [ do
        maybeExitCode <- getProcessExitCode processHandle
        when (isNothing maybeExitCode) (terminateProcess processHandle),
      void (waitForProcess processHandle)
    ]

-- | Start the Apple host engine daemon from the installed operator CLI rather
-- than by re-executing this suite.
--
-- The host inference daemon is a host-reserve claimant and carries no toolchain
-- heap ceiling; this suite is a non-unit test component and carries a baked
-- 1024 MiB one. Re-executing this image as the daemon gave inference the test
-- lane's ceiling, and a real result larger than it killed the consumer loop with
-- a heap overflow the moment the first model completed. The two process images
-- are kept apart so that ceiling cannot reach inference again.
withRuntimeServiceDaemon :: Paths -> IO a -> IO a
withRuntimeServiceDaemon paths action = do
  infernixExecutable <- resolveHostServiceDaemonExecutable paths
  let logPath = hostServiceDaemonLogPath paths
  reportStep ("apple host service daemon log: " <> logPath)
  reportStep ("apple host service daemon executable: " <> infernixExecutable)
  withLoggedServiceDaemon
    paths
    infernixExecutable
    ["service"]
    logPath
    (\_processHandle _logPath -> action)

-- | The installed operator CLI under the configured build root. It is a fixed
-- path rather than a discovered one, and its absence is a named refusal: a
-- daemon started from anything else is not the image the operator runs.
resolveHostServiceDaemonExecutable :: Paths -> IO FilePath
resolveHostServiceDaemonExecutable paths = do
  let daemonExecutable = buildRoot paths </> "infernix"
  present <- doesFileExist daemonExecutable
  runnable <-
    if present
      then executable <$> getPermissions daemonExecutable
      else pure False
  unless
    runnable
    ( ioError
        ( userError
            ( "the apple host service daemon requires the installed operator CLI at "
                <> daemonExecutable
                <> "; build it through the governed bootstrap before the harness runs"
            )
        )
    )
  pure daemonExecutable

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

-- Phase 6 Sprint 6.47 retained this case when the failure-injection tail was
-- deleted. Its subject is **storage determinism**, not availability: the PV
-- inventory and the PVC rebinding identity across a lifecycle cycle, which is
-- Phase 2 doctrine. It injects no failure and does not depend on a replica.
validatePostgresLifecycleRebinding :: Paths -> RuntimeMode -> ClusterState -> IO ()
validatePostgresLifecycleRebinding paths runtimeMode state = do
  inventoryBefore <- postgresPersistentVolumeInventory state
  assert (not (Map.null inventoryBefore)) "operator-managed PostgreSQL persistent-volume inventory is present before cluster lifecycle rebind validation"
  boundVolumesBefore <- postgresBoundVolumeNames state
  assert (boundVolumesBefore == Map.keysSet inventoryBefore) "operator-managed PostgreSQL PVCs bind to the full deterministic Harbor PV inventory before cluster lifecycle rebind validation"
  clusterDownHarness (Just runtimeMode)
  clusterUpHarness (Just runtimeMode)
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

parseNonNegativeInt :: String -> String -> Int
parseNonNegativeInt label value =
  case reads value of
    [(parsed, "")] | parsed >= (0 :: Int) -> parsed
    _ -> error ("unable to parse " <> label <> " as a non-negative integer: " <> value)

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

data PodNodePlacement = PodNodePlacement
  { podNodePlacementPodName :: String,
    podNodePlacementNodeName :: String,
    podNodePlacementPhase :: String
  }
  deriving (Eq, Show)

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
