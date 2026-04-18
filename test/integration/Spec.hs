{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (finally)
import Data.ByteString.Lazy qualified as Lazy
import Data.List (isInfixOf, isPrefixOf, tails)
import Data.Text qualified as Text
import Data.Text.IO qualified as TextIO
import Infernix.Cluster
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.Models
import Infernix.Service (activateHostBridgeRoute, restoreClusterServiceRoute)
import Infernix.Types
import System.Directory
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (Handle, hClose, hGetLine)
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process
  ( CreateProcess (std_err, std_in, std_out),
    StdStream (CreatePipe),
    createProcess,
    proc,
    readCreateProcessWithExitCode,
    readProcess,
    readProcessWithExitCode,
    terminateProcess,
    waitForProcess,
  )

data SerializedCatalogEntry = SerializedCatalogEntry
  { entryMatrixRowId :: Text.Text,
    entryModelId :: Text.Text,
    entrySelectedEngine :: Text.Text,
    entryRuntimeMode :: RuntimeMode,
    entryRequiresGpu :: Bool
  }

main :: IO ()
main = withTestRoot ".tmp/integration" $ do
  paths <- Config.discoverPaths
  maybeRequestedMode <- lookupEnv "INFERNIX_RUNTIME_MODE"
  runtimeModes <- case maybeRequestedMode >>= (parseRuntimeMode . Text.pack) of
    Just runtimeMode -> pure [runtimeMode]
    Nothing -> pure allRuntimeModes
  mapM_ (exerciseRuntimeMode paths) runtimeModes
  case runtimeModes of
    runtimeMode : _ -> validateEdgePortConflictAndRediscovery paths runtimeMode
    [] -> fail "integration suite requires at least one runtime mode"
  putStrLn "integration tests passed"

exerciseRuntimeMode :: Paths -> RuntimeMode -> IO ()
exerciseRuntimeMode paths runtimeMode = do
  clusterUp (Just runtimeMode)
  validateClusterArtifacts paths runtimeMode
  validateClusterStatusOutput paths runtimeMode
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available after cluster up") pure maybeState
  let baseUrl = edgeBaseUrl paths (edgePort state)
  serializedEntries <- loadSerializedCatalogEntries paths runtimeMode
  assert (not (null serializedEntries)) ("serialized catalog is non-empty for " <> showRuntimeMode runtimeMode)
  let typedCatalog = catalogForMode runtimeMode
      typedModelIds = map modelId typedCatalog
      serializedModelIds = map entryModelId serializedEntries
      typedEngines = map selectedEngine typedCatalog
      serializedEngines = map entrySelectedEngine serializedEntries
  assert (serializedModelIds == typedModelIds) ("serialized catalog preserves model ordering for " <> showRuntimeMode runtimeMode)
  assert (serializedEngines == typedEngines) ("serialized catalog preserves engine bindings for " <> showRuntimeMode runtimeMode)
  validateRoutedSurface paths runtimeMode serializedEntries
  whenHostNative paths (validateHostBridgeService paths runtimeMode serializedEntries)
  case serializedEntries of
    firstEntry : _ -> validateServiceCacheLifecycle paths runtimeMode baseUrl firstEntry
    [] -> pure ()
  mapM_ (exerciseCatalogEntry baseUrl runtimeMode) serializedEntries
  case (runtimeMode, serializedEntries) of
    (AppleSilicon, firstEntry : _) -> validateHaRecovery paths runtimeMode baseUrl firstEntry
    _ -> pure ()
  case runtimeMode of
    LinuxCuda -> do
      assert (any entryRequiresGpu serializedEntries) "linux-cuda serialized catalogs record GPU-bound rows"
      validateLinuxCudaCluster paths runtimeMode
    _ -> pure ()
  clusterDown (Just runtimeMode)
  maybeDownState <- loadClusterState paths
  assert (maybe False (not . clusterPresent) maybeDownState) ("cluster down records cluster absence for " <> showRuntimeMode runtimeMode)
  downStatusOutput <- captureInfernixOutput paths runtimeMode ["cluster", "status"]
  assert ("clusterPresent: False" `isInfixOf` downStatusOutput) ("cluster status reports cluster absence after down for " <> showRuntimeMode runtimeMode)
  clusterUp (Just runtimeMode)
  maybeStateAfterRepeatUp <- loadClusterState paths
  assert (maybe False clusterPresent maybeStateAfterRepeatUp) ("repeat cluster up remains idempotent for " <> showRuntimeMode runtimeMode)
  clusterDown (Just runtimeMode)

exerciseCatalogEntry :: String -> RuntimeMode -> SerializedCatalogEntry -> IO ()
exerciseCatalogEntry baseUrl runtimeMode entry = do
  response <-
    httpPostJsonWithRetry
      20
      (baseUrl <> "/api/inference")
      ("{\"requestModelId\":\"" <> Text.unpack (entryModelId entry) <> "\",\"inputText\":\"integration coverage\"}")
  assert (("\"resultModelId\": \"" <> Text.unpack (entryModelId entry) <> "\"") `isInfixOf` response) "integration exercises every generated catalog entry through the routed service API"
  assert (("\"matrixRowId\": \"" <> Text.unpack (entryMatrixRowId entry) <> "\"") `isInfixOf` response) "integration preserves serialized matrix row ids through the routed service API"
  assert (("\"runtimeMode\": \"" <> showRuntimeMode runtimeMode <> "\"") `isInfixOf` response) "integration preserves serialized runtime modes through the routed service API"
  assert (("\"selectedEngine\": \"" <> Text.unpack (entrySelectedEngine entry) <> "\"") `isInfixOf` response) "integration preserves serialized engine bindings through the routed service API"
  requestIdText <- requireJsonStringField "requestId" response
  storedResult <- httpGetWithRetry 20 (baseUrl <> "/api/inference/" <> requestIdText)
  assert (("\"resultModelId\": \"" <> Text.unpack (entryModelId entry) <> "\"") `isInfixOf` storedResult) "integration can reload persisted routed service results"

validateClusterArtifacts :: Paths -> RuntimeMode -> IO ()
validateClusterArtifacts paths runtimeMode = do
  kubeconfigExists <- doesFileExist (Config.generatedKubeconfigPath paths)
  generatedCatalogExists <- doesFileExist (Config.generatedDemoConfigPath paths runtimeMode)
  publishedCatalogExists <- doesFileExist (Config.publishedConfigMapCatalogPath paths runtimeMode)
  configMapManifestExists <- doesFileExist (Config.publishedConfigMapManifestPath paths)
  publicationStateExists <- doesFileExist (Config.publicationStatePath paths)
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available after cluster up") pure maybeState

  assert kubeconfigExists "cluster up creates a repo-local kubeconfig"
  assert generatedCatalogExists "cluster up creates the generated mode-specific demo config"
  assert publishedCatalogExists "cluster up publishes the generated catalog into the ConfigMap mirror path"
  assert configMapManifestExists "cluster up writes the ConfigMap compatibility manifest"
  assert publicationStateExists "cluster up writes publication state for routed consumers"
  assert (clusterPresent state) "cluster up persists cluster state"

  generatedPayload <- Lazy.readFile (Config.generatedDemoConfigPath paths runtimeMode)
  publishedPayload <- Lazy.readFile (Config.publishedConfigMapCatalogPath paths runtimeMode)
  configMapNameOutput <- kubectlOutputForState state ["get", "configmap", "infernix-demo-config", "-n", "platform", "-o", "name"]
  publicationPayload <- readFileWithRetry 5 (Config.publicationStatePath paths)
  assert (generatedPayload == publishedPayload) "published ConfigMap content matches the generated catalog byte-for-byte"
  assert ("configmap/infernix-demo-config" `isInfixOf` configMapNameOutput) "real ConfigMap publication exists in the cluster"
  assert (("\"runtimeMode\": \"" <> showRuntimeMode runtimeMode <> "\"") `isInfixOf` publicationPayload) "publication state records the active runtime mode"
  assert ("\"path\": \"/api\"" `isInfixOf` publicationPayload) "publication state records routed API publication"

validateClusterStatusOutput :: Paths -> RuntimeMode -> IO ()
validateClusterStatusOutput paths runtimeMode = do
  statusOutput <- captureInfernixOutput paths runtimeMode ["cluster", "status"]
  assert ("clusterPresent: True" `isInfixOf` statusOutput) "cluster status reports cluster presence"
  assert (("runtimeMode: " <> showRuntimeMode runtimeMode) `isInfixOf` statusOutput) "cluster status reports the active runtime mode"
  assert (("publicationStatePath: " <> Config.publicationStatePath paths) `isInfixOf` statusOutput) "cluster status reports the publication-state path"
  assert (("generatedDemoConfigPath: " <> Config.generatedDemoConfigPath paths runtimeMode) `isInfixOf` statusOutput) "cluster status reports the generated demo-config path"
  assert (("publishedDemoConfigPath: " <> Config.publishedConfigMapCatalogPath paths runtimeMode) `isInfixOf` statusOutput) "cluster status reports the published demo-config path"
  assert (("mountedDemoConfigPath: " <> Config.watchedDemoConfigPath runtimeMode) `isInfixOf` statusOutput) "cluster status reports the mounted demo-config path"
  assert ("route: /api -> Service API" `isInfixOf` statusOutput) "cluster status reports the routed API publication"

validateLinuxCudaCluster :: Paths -> RuntimeMode -> IO ()
validateLinuxCudaCluster paths runtimeMode = do
  allocatableOutput <-
    captureInfernixOutput
      paths
      runtimeMode
      ["kubectl", "get", "nodes", "-l", "infernix.runtime/gpu=true", "-o", "jsonpath={range .items[*]}{.status.allocatable.nvidia\\.com/gpu}{\"\\n\"}{end}"]
  let allocatableValues = filter (`elem` ["0", "1"]) (map trim (lines allocatableOutput))
  assert (not (null allocatableValues)) "linux-cuda nodes advertise at least one GPU allocatable value"
  assert (all (== "1") allocatableValues) "linux-cuda nodes advertise nvidia.com/gpu allocatable values"
  runtimeClassName <-
    captureInfernixOutput
      paths
      runtimeMode
      ["kubectl", "-n", "platform", "get", "deployment", "infernix-service", "-o", "jsonpath={.spec.template.spec.runtimeClassName}"]
  assert (trim runtimeClassName == "nvidia") "linux-cuda service pods use the nvidia runtime class"
  gpuRequest <-
    captureInfernixOutput
      paths
      runtimeMode
      ["kubectl", "-n", "platform", "get", "deployment", "infernix-service", "-o", "jsonpath={.spec.template.spec.containers[0].resources.requests.nvidia\\.com/gpu}"]
  assert (trim gpuRequest == "1") "linux-cuda service pods request nvidia.com/gpu"

validateRoutedSurface :: Paths -> RuntimeMode -> [SerializedCatalogEntry] -> IO ()
validateRoutedSurface paths runtimeMode serializedEntries = do
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available after cluster up") pure maybeState
  let baseUrl = edgeBaseUrl paths (edgePort state)
  homeResponse <- httpGetWithRetry 60 (baseUrl <> "/")
  publicationResponse <- httpGetWithRetry 60 (baseUrl <> "/api/publication")
  modelsResponse <- httpGetWithRetry 60 (baseUrl <> "/api/models")
  harborResponse <- httpGetWithRetry 60 (baseUrl <> "/harbor")
  minioResponse <- httpGetWithRetry 60 (baseUrl <> "/minio/s3")
  pulsarResponse <- httpGetWithRetry 60 (baseUrl <> "/pulsar/ws")
  assert ("Infernix" `isInfixOf` homeResponse) "routed edge serves the browser workbench"
  assert (("\"runtimeMode\": \"" <> showRuntimeMode runtimeMode <> "\"") `isInfixOf` publicationResponse) "routed publication reports the active runtime mode"
  assert ("\"daemonLocation\": \"cluster-pod\"" `isInfixOf` publicationResponse) "routed publication reports the cluster-resident daemon"
  assert ("\"mode\": \"cluster-service\"" `isInfixOf` publicationResponse) "routed publication reports the cluster service as the active API upstream"
  assert ("\"durableBackendAccessMode\": \"cluster-local\"" `isInfixOf` publicationResponse) "cluster-resident service reports cluster-local durable backend access"
  assert ("\"id\": \"minio\"" `isInfixOf` publicationResponse && "\"durableBackendState\": \"minio-backed chart deployment\"" `isInfixOf` publicationResponse) "routed publication reports MinIO upstream backing state"
  assert ("\"id\": \"pulsar\"" `isInfixOf` publicationResponse && "\"durableBackendState\": \"pulsar-backed chart deployment\"" `isInfixOf` publicationResponse) "routed publication reports Pulsar upstream backing state"
  assert ("Harbor Gateway" `isInfixOf` harborResponse || "Harbor" `isInfixOf` harborResponse) "routed Harbor portal resolves through the cluster gateway"
  assert ("\"targetUrl\"" `isInfixOf` minioResponse || "\"status\": \"ready\"" `isInfixOf` minioResponse) "routed MinIO surface resolves through the cluster gateway"
  assert ("\"brokersHealth\"" `isInfixOf` pulsarResponse || "\"status\": \"ready\"" `isInfixOf` pulsarResponse) "routed Pulsar surface resolves through the cluster gateway"
  mapM_
    (\entry -> assert (Text.unpack (entryModelId entry) `isInfixOf` modelsResponse) "routed model listing exposes every serialized catalog entry")
    serializedEntries

validateHostBridgeService :: Paths -> RuntimeMode -> [SerializedCatalogEntry] -> IO ()
validateHostBridgeService paths runtimeMode serializedEntries = do
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available before host-bridge validation") pure maybeState
  let baseUrl = edgeBaseUrl paths (edgePort state)
  activateHostBridgeRoute paths runtimeMode 18081
  let processArgs =
        [ repoRoot paths </> "tools" </> "service_server.py",
          "--repo-root",
          repoRoot paths,
          "--host",
          "0.0.0.0",
          "--port",
          "18081",
          "--runtime-mode",
          showRuntimeMode runtimeMode,
          "--control-plane-context",
          "host-native",
          "--daemon-location",
          "control-plane-host",
          "--catalog-source",
          "generated-build-root",
          "--demo-config",
          Config.generatedDemoConfigPath paths runtimeMode,
          "--mounted-demo-config",
          Config.watchedDemoConfigPath runtimeMode,
          "--publication-state",
          Config.publicationStatePath paths,
          "--route-probe-base-url",
          "http://127.0.0.1:" <> show (edgePort state)
        ]
  (_, _, _, serviceHandle) <- createProcess (proc "python3" processArgs)
  publicationResponse <- waitForPublicationState baseUrl "control-plane-host" "host-daemon-bridge"
  modelsResponse <- httpGetWithRetry 20 (baseUrl <> "/api/models")
  assert ("\"daemonLocation\": \"control-plane-host\"" `isInfixOf` publicationResponse) "host bridge publishes the host daemon location through the routed API"
  assert ("\"mode\": \"host-daemon-bridge\"" `isInfixOf` publicationResponse) "host bridge publishes the host-daemon API upstream"
  assert ("\"durableBackendAccessMode\": \"edge-route-bridge\"" `isInfixOf` publicationResponse) "host bridge publishes edge-routed durable backend access"
  assert ("\"id\": \"harbor\"" `isInfixOf` publicationResponse && "\"healthStatus\": \"ready\"" `isInfixOf` publicationResponse) "host-native service publication reports routed Harbor health"
  mapM_
    (\entry -> assert (Text.unpack (entryModelId entry) `isInfixOf` modelsResponse) "host bridge preserves routed catalog listing through the same edge entrypoint")
    serializedEntries
  case serializedEntries of
    firstEntry : _ -> do
      inferenceResponse <-
        httpPostJsonWithRetry
          20
          (baseUrl <> "/api/inference")
          ("{\"requestModelId\":\"" <> Text.unpack (entryModelId firstEntry) <> "\",\"inputText\":\"host bridge coverage\"}")
      assert (("\"resultModelId\": \"" <> Text.unpack (entryModelId firstEntry) <> "\"") `isInfixOf` inferenceResponse) "host bridge preserves routed inference through the browser-visible edge entrypoint"
    [] -> pure ()
  terminateProcess serviceHandle
  _ <- waitForProcess serviceHandle
  restoreClusterServiceRoute paths
  _ <- waitForPublicationState baseUrl "cluster-pod" "cluster-service"
  pure ()

whenHostNative :: Paths -> IO () -> IO ()
whenHostNative paths action
  | Config.controlPlaneContext paths == "host-native" = action
  | otherwise = pure ()

validateServiceCacheLifecycle :: Paths -> RuntimeMode -> String -> SerializedCatalogEntry -> IO ()
validateServiceCacheLifecycle paths runtimeMode baseUrl entry = do
  let modelIdText = Text.unpack (entryModelId entry)
      inferenceBody =
        "{\"requestModelId\":\"" <> modelIdText <> "\",\"inputText\":\"cache lifecycle coverage\"}"
      cacheBody = "{\"modelId\":\"" <> modelIdText <> "\"}"
  inferenceResponse <- httpPostJsonWithRetry 20 (baseUrl <> "/api/inference") inferenceBody
  assert (("\"resultModelId\": \"" <> modelIdText <> "\"") `isInfixOf` inferenceResponse) "routed inference succeeds before cache lifecycle assertions"
  cacheAfterInference <- httpGetWithRetry 20 (baseUrl <> "/api/cache")
  assert (("\"modelId\": \"" <> modelIdText <> "\"") `isInfixOf` cacheAfterInference) "service cache status lists the materialized model"
  assert ("\"materialized\": true" `isInfixOf` cacheAfterInference) "service cache status records materialized cache entries"
  evictResponse <- httpPostJsonWithRetry 20 (baseUrl <> "/api/cache/evict") cacheBody
  assert ("\"evictedCount\": 1" `isInfixOf` evictResponse) "service cache eviction reports one evicted entry"
  cacheAfterEvict <- httpGetWithRetry 20 (baseUrl <> "/api/cache")
  assert (("\"modelId\": \"" <> modelIdText <> "\"") `isInfixOf` cacheAfterEvict) "service cache status preserves durable manifests after eviction"
  assert ("\"materialized\": false" `isInfixOf` cacheAfterEvict) "service cache eviction removes the derived cache marker"
  rebuildResponse <- httpPostJsonWithRetry 20 (baseUrl <> "/api/cache/rebuild") cacheBody
  assert ("\"rebuiltCount\": 1" `isInfixOf` rebuildResponse) "service cache rebuild reports one rebuilt entry"
  cacheAfterRebuild <- httpGetWithRetry 20 (baseUrl <> "/api/cache")
  assert ("\"materialized\": true" `isInfixOf` cacheAfterRebuild) "service cache rebuild restores the derived cache marker"
  requestIdText <- requireJsonStringField "requestId" inferenceResponse
  maybeObjectRef <- extractJsonNullableStringField "objectRef" inferenceResponse
  validateDurableBackends paths runtimeMode baseUrl modelIdText requestIdText maybeObjectRef

validateHaRecovery :: Paths -> RuntimeMode -> String -> SerializedCatalogEntry -> IO ()
validateHaRecovery paths runtimeMode baseUrl entry = do
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available before HA recovery validation") pure maybeState
  let modelIdText = Text.unpack (entryModelId entry)
      longInferenceBody =
        "{\"requestModelId\":\""
          <> modelIdText
          <> "\",\"inputText\":\""
          <> replicate 160 'h'
          <> "\"}"
  inferenceResponse <- httpPostJsonWithRetry 20 (baseUrl <> "/api/inference") longInferenceBody
  requestIdText <- requireJsonStringField "requestId" inferenceResponse
  maybeObjectRef <- extractJsonNullableStringField "objectRef" inferenceResponse
  validateHarborRecovery state baseUrl
  validateMinioRecovery paths state runtimeMode modelIdText requestIdText maybeObjectRef
  validatePulsarRecovery paths runtimeMode state baseUrl modelIdText

validateHarborRecovery :: ClusterState -> String -> IO ()
validateHarborRecovery state baseUrl = do
  corePodName <- firstPodWithPrefix state "infernix-harbor-core-"
  publishedServiceImage <-
    kubectlOutputForState state ["-n", "platform", "get", "deployment/infernix-service", "-o", "jsonpath={.spec.template.spec.containers[0].image}"]
  runKubectlForState state ["-n", "platform", "delete", "pod", corePodName, "--wait=true"]
  waitForRollout state "deployment/infernix-harbor-core" 240
  harborResponse <- httpGetWithRetry 40 (baseUrl <> "/harbor")
  assert ("Harbor Gateway" `isInfixOf` harborResponse || "Harbor" `isInfixOf` harborResponse) "Harbor portal survives single core-pod replacement"
  runKubectlForState state ["-n", "platform", "delete", "pod", "harbor-pull-smoke", "--ignore-not-found=true"]
  runKubectlInputForState state ["-n", "platform", "apply", "-f", "-"] (renderHarborPullSmokePod (trim publishedServiceImage))
  waitForPodReady state "harbor-pull-smoke" 240
  runKubectlForState state ["-n", "platform", "delete", "pod", "harbor-pull-smoke", "--wait=true"]

validateMinioRecovery :: Paths -> ClusterState -> RuntimeMode -> String -> String -> Maybe String -> IO ()
validateMinioRecovery paths state runtimeMode modelIdText requestIdText maybeObjectRef = do
  runKubectlForState state ["-n", "platform", "delete", "pod", "infernix-minio-0", "--wait=true"]
  waitForRollout state "statefulset/infernix-minio" 300
  runtimeResultExists <- minioObjectExists paths "infernix-runtime" ("results/" <> requestIdText <> ".pb")
  assert runtimeResultExists "MinIO runtime results survive single MinIO pod replacement"
  case maybeObjectRef of
    Nothing -> pure ()
    Just objectRefText -> do
      largeOutputExists <- minioObjectExists paths "infernix-results" objectRefText
      assert largeOutputExists "MinIO large-output objects survive single MinIO pod replacement"
  manifestExists <- minioObjectExists paths "infernix-runtime" ("manifests/" <> showRuntimeMode runtimeMode <> "/" <> modelIdText <> "/default.pb")
  assert manifestExists "MinIO protobuf cache manifests survive single MinIO pod replacement"

validatePulsarRecovery :: Paths -> RuntimeMode -> ClusterState -> String -> String -> IO ()
validatePulsarRecovery paths runtimeMode state baseUrl modelIdText = do
  runKubectlForState state ["-n", "platform", "delete", "pod", "infernix-infernix-pulsar-proxy-0", "--wait=true"]
  waitForRollout state "statefulset/infernix-infernix-pulsar-proxy" 300
  inferenceResponse <-
    httpPostJsonWithRetry
      40
      (baseUrl <> "/api/inference")
      ("{\"requestModelId\":\"" <> modelIdText <> "\",\"inputText\":\"pulsar recovery coverage\"}")
  assert (("\"resultModelId\": \"" <> modelIdText <> "\"") `isInfixOf` inferenceResponse) "routed inference survives single Pulsar proxy replacement"
  requestIdText <- requireJsonStringField "requestId" inferenceResponse
  maybeObjectRef <- extractJsonNullableStringField "objectRef" inferenceResponse
  validateDurableBackends paths runtimeMode baseUrl modelIdText requestIdText maybeObjectRef

validateEdgePortConflictAndRediscovery :: Paths -> RuntimeMode -> IO ()
validateEdgePortConflictAndRediscovery paths runtimeMode = do
  cleanupRuntimeState paths
  (busyPortStdin, busyPortStdout, busyPortStderr, busyPortProcess) <-
    createProcess
      (proc "python3" ["-c", busyPortScript])
        { std_in = CreatePipe,
          std_out = CreatePipe,
          std_err = CreatePipe
        }
  case (busyPortStdin, busyPortStdout, busyPortStderr) of
    (Just stdinHandle, Just stdoutHandle, Just _) -> do
      readyLine <- hGetLineWithRetry 20 stdoutHandle
      assert (readyLine == "ready") "port-conflict helper binds 9090 before cluster up runs"
      clusterUp (Just runtimeMode)
      maybeBusyState <- loadClusterState paths
      assert (maybe False ((== 9091) . edgePort) maybeBusyState) "cluster up selects the next open port when 9090 is busy"
      clusterDown (Just runtimeMode)
      hClose stdinHandle
      terminateProcess busyPortProcess
      _ <- waitForProcess busyPortProcess
      clusterUp (Just runtimeMode)
      maybeRediscoveredState <- loadClusterState paths
      assert (maybe False ((== 9091) . edgePort) maybeRediscoveredState) "cluster up reuses the previously published edge port after restart"
      clusterDown (Just runtimeMode)
    _ -> fail "port-conflict helper failed to expose the readiness pipe"
  where
    busyPortScript =
      unlines
        [ "import socket",
          "import sys",
          "sock = socket.socket()",
          "sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)",
          "sock.bind(('127.0.0.1', 9090))",
          "sock.listen(1)",
          "print('ready', flush=True)",
          "try:",
          "    sys.stdin.read()",
          "finally:",
          "    sock.close()"
        ]

cleanupRuntimeState :: Paths -> IO ()
cleanupRuntimeState paths = do
  catchIOError (removePathForcibly (runtimeRoot paths)) ignoreMissing
  createDirectoryIfMissing True (runtimeRoot paths)
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

loadSerializedCatalogEntries :: Paths -> RuntimeMode -> IO [SerializedCatalogEntry]
loadSerializedCatalogEntries paths runtimeMode = do
  output <-
    readProcess
      "python3"
      [ repoRoot paths </> "tools" </> "demo_config.py",
        "--list-models",
        Config.generatedDemoConfigPath paths runtimeMode
      ]
      ""
  case lines output of
    runtimeLine : entryLines -> do
      let runtimeParts = splitTabs runtimeLine
      case runtimeParts of
        ["runtimeMode", runtimeModeIdText] ->
          assert (runtimeModeIdText == showRuntimeMode runtimeMode) "serialized catalog reports the requested runtime mode"
        _ -> fail "serialized demo config did not report a runtimeMode header"
      mapM parseEntryLine entryLines
    [] -> fail "serialized demo config summary was empty"

parseEntryLine :: String -> IO SerializedCatalogEntry
parseEntryLine entryLine =
  case splitTabs entryLine of
    ["model", matrixRowIdText, modelIdText, selectedEngineText, runtimeModeText, requiresGpuText] ->
      case parseRuntimeMode (Text.pack runtimeModeText) of
        Nothing -> fail ("serialized catalog entry has an unsupported runtime mode: " <> runtimeModeText)
        Just runtimeMode ->
          pure
            SerializedCatalogEntry
              { entryMatrixRowId = Text.pack matrixRowIdText,
                entryModelId = Text.pack modelIdText,
                entrySelectedEngine = Text.pack selectedEngineText,
                entryRuntimeMode = runtimeMode,
                entryRequiresGpu = requiresGpuText == "true"
              }
    _ -> fail ("serialized demo config summary line was malformed: " <> entryLine)

splitTabs :: String -> [String]
splitTabs [] = [""]
splitTabs value =
  let (prefix, suffix) = break (== '\t') value
   in case suffix of
        [] -> [prefix]
        _ : rest -> prefix : splitTabs rest

captureInfernixOutput :: Paths -> RuntimeMode -> [String] -> IO String
captureInfernixOutput paths runtimeMode args = do
  let binaryPath = buildRoot paths </> "infernix"
  binaryExists <- doesFileExist binaryPath
  let commandAndArgs
        | binaryExists =
            ( binaryPath,
              ["--runtime-mode", showRuntimeMode runtimeMode] <> args
            )
        | otherwise =
            ( repoRoot paths </> "cabalw",
              [ "run",
                "exe:infernix",
                "--",
                "--runtime-mode",
                showRuntimeMode runtimeMode
              ]
                <> args
            )
  (exitCode, stdoutOutput, stderrOutput) <- uncurry readProcessWithExitCode commandAndArgs ""
  assert (null stderrOutput || exitCode == ExitSuccess) "cluster status does not emit stderr output"
  case exitCode of
    ExitSuccess -> pure stdoutOutput
    _ -> fail ("infernix command failed: " <> unlines [stdoutOutput, stderrOutput])

hGetLineWithRetry :: Int -> Handle -> IO String
hGetLineWithRetry retries handle =
  catchIOError
    (hGetLine handle)
    ( \err ->
        if retries <= 0
          then ioError err
          else do
            threadDelay 100000
            hGetLineWithRetry (retries - 1) handle
    )

withTestRoot :: FilePath -> IO a -> IO a
withTestRoot root action = do
  catchIOError (removePathForcibly root) ignoreMissing
  createDirectoryIfMissing True root
  previousDataRoot <- lookupEnv "INFERNIX_DATA_ROOT"
  setEnv "INFERNIX_DATA_ROOT" (root </> ".data")
  withCurrentDirectory root action
    `finally` maybe (unsetEnv "INFERNIX_DATA_ROOT") (setEnv "INFERNIX_DATA_ROOT") previousDataRoot
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

assert :: Bool -> String -> IO ()
assert True _ = pure ()
assert False message = fail message

showRuntimeMode :: RuntimeMode -> String
showRuntimeMode = Text.unpack . runtimeModeId

edgeBaseUrl :: Paths -> Int -> String
edgeBaseUrl paths port =
  "http://"
    <> runtimeHost paths
    <> ":"
    <> show port

runtimeHost :: Paths -> String
runtimeHost paths
  | Config.controlPlaneContext paths == "outer-container" = "host.docker.internal"
  | otherwise = "127.0.0.1"

kubectlOutputForState :: ClusterState -> [String] -> IO String
kubectlOutputForState state args =
  readProcess "kubectl" (["--kubeconfig", kubeconfigPath state] <> args) ""

runKubectlForState :: ClusterState -> [String] -> IO ()
runKubectlForState state args = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readProcessWithExitCode "kubectl" (["--kubeconfig", kubeconfigPath state] <> args) ""
  case exitCode of
    ExitSuccess -> pure ()
    _ -> fail ("kubectl command failed: " <> unwords args <> "\n" <> stdoutOutput <> stderrOutput)

runKubectlInputForState :: ClusterState -> [String] -> String -> IO ()
runKubectlInputForState state args inputPayload = do
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc "kubectl" (["--kubeconfig", kubeconfigPath state] <> args))
      inputPayload
  case exitCode of
    ExitSuccess -> pure ()
    _ -> fail ("kubectl command failed: " <> unwords args <> "\n" <> stdoutOutput <> stderrOutput)

waitForRollout :: ClusterState -> String -> Int -> IO ()
waitForRollout state workload timeoutSeconds =
  runKubectlForState state ["-n", "platform", "rollout", "status", workload, "--timeout", show timeoutSeconds <> "s"]

waitForPodReady :: ClusterState -> String -> Int -> IO ()
waitForPodReady state podName timeoutSeconds =
  runKubectlForState state ["-n", "platform", "wait", "--for=condition=Ready", "pod/" <> podName, "--timeout", show timeoutSeconds <> "s"]

firstPodWithPrefix :: ClusterState -> String -> IO String
firstPodWithPrefix state prefix = do
  podNames <- lines <$> kubectlOutputForState state ["-n", "platform", "get", "pods", "--no-headers", "-o", "custom-columns=:metadata.name"]
  case filter (prefix `isPrefixOf`) podNames of
    podName : _ -> pure podName
    [] -> fail ("no pod matched prefix " <> prefix)

renderHarborPullSmokePod :: String -> String
renderHarborPullSmokePod imageRef =
  unlines
    [ "apiVersion: v1",
      "kind: Pod",
      "metadata:",
      "  name: harbor-pull-smoke",
      "  namespace: platform",
      "spec:",
      "  restartPolicy: Never",
      "  containers:",
      "    - name: smoke",
      "      image: " <> imageRef,
      "      command:",
      "        - python3",
      "        - -c",
      "        - import time; print('ready', flush=True); time.sleep(30)"
    ]

httpGetWithRetry :: Int -> String -> IO String
httpGetWithRetry retries url =
  catchIOError
    (readProcess "curl" ["-fsS", url] "")
    ( \err ->
        if retries <= 0
          then ioError err
          else do
            threadDelay 500000
            httpGetWithRetry (retries - 1) url
    )

httpPostJson :: String -> String -> IO String
httpPostJson url payload =
  readProcess
    "curl"
    [ "-fsS",
      "-X",
      "POST",
      "-H",
      "Content-Type: application/json",
      "-d",
      payload,
      url
    ]
    ""

httpPostJsonWithRetry :: Int -> String -> String -> IO String
httpPostJsonWithRetry retries url payload =
  catchIOError
    (httpPostJson url payload)
    ( \err ->
        if retries <= 0
          then ioError err
          else do
            threadDelay 500000
            httpPostJsonWithRetry (retries - 1) url payload
    )

waitForPublicationState :: String -> String -> String -> IO String
waitForPublicationState baseUrl expectedDaemonLocation expectedApiUpstreamMode = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          fail
            ( "timed out waiting for publication state "
                <> expectedDaemonLocation
                <> " / "
                <> expectedApiUpstreamMode
            )
      | otherwise = do
          response <-
            catchIOError
              (httpGetWithRetry 1 (baseUrl <> "/api/publication"))
              (\_ -> pure "")
          if ("\"daemonLocation\": \"" <> expectedDaemonLocation <> "\"") `isInfixOf` response
            && ("\"mode\": \"" <> expectedApiUpstreamMode <> "\"") `isInfixOf` response
            then pure response
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)

readFileWithRetry :: Int -> FilePath -> IO String
readFileWithRetry retries filePath =
  catchIOError
    (Text.unpack <$> TextIO.readFile filePath)
    ( \err ->
        if retries <= 0
          then ioError err
          else do
            threadDelay 100000
            readFileWithRetry (retries - 1) filePath
    )

validateDurableBackends :: Paths -> RuntimeMode -> String -> String -> String -> Maybe String -> IO ()
validateDurableBackends paths runtimeMode baseUrl modelIdText requestIdText maybeObjectRef = do
  requestSchema <- httpGetWithRetry 20 (baseUrl <> "/pulsar/admin/schemas/public/default/infernix-inference-requests/schema")
  resultSchema <- httpGetWithRetry 20 (baseUrl <> "/pulsar/admin/schemas/public/default/infernix-inference-results/schema")
  coordinationSchema <- httpGetWithRetry 20 (baseUrl <> "/pulsar/admin/schemas/public/default/infernix-runtime-manifests/schema")
  let protobufSchemaPublished response messageName =
        ("\"type\":\"PROTOBUF\"" `isInfixOf` response || "\"type\": \"PROTOBUF\"" `isInfixOf` response)
          && messageName `isInfixOf` response
  assert (protobufSchemaPublished requestSchema "InferenceRequest") "Pulsar request topic publishes the protobuf request schema"
  assert (protobufSchemaPublished resultSchema "InferenceResult") "Pulsar result topic publishes the protobuf result schema"
  assert (protobufSchemaPublished coordinationSchema "RuntimeManifest") "Pulsar coordination topic publishes the protobuf manifest schema"
  runtimeResultExists <- minioObjectExists paths "infernix-runtime" ("results/" <> requestIdText <> ".pb")
  manifestExists <- minioObjectExists paths "infernix-runtime" ("manifests/" <> showRuntimeMode runtimeMode <> "/" <> modelIdText <> "/default.pb")
  assert runtimeResultExists "MinIO stores protobuf inference results for the routed service path"
  assert manifestExists "MinIO stores protobuf cache manifests for the routed service path"
  case maybeObjectRef of
    Nothing -> pure ()
    Just objectRefText -> do
      largeOutputExists <- minioObjectExists paths "infernix-results" objectRefText
      assert largeOutputExists "MinIO stores large-output object payloads for the routed service path"

minioObjectExists :: Paths -> String -> String -> IO Bool
minioObjectExists paths bucketName objectKey = waitForObject (20 :: Int)
  where
    waitForObject attempts = do
      objectExists <- probeObject
      if objectExists || attempts <= 1
        then pure objectExists
        else do
          threadDelay 500000
          waitForObject (attempts - 1)

    probeObject = do
      let script =
            unlines
              [ "import sys",
                "from minio import Minio",
                "from minio.error import S3Error",
                "client = Minio(sys.argv[1], access_key='minioadmin', secret_key='minioadmin123', secure=False)",
                "try:",
                "    client.stat_object(sys.argv[2], sys.argv[3])",
                "except S3Error as exc:",
                "    if exc.code == 'NoSuchKey':",
                "        print('false')",
                "    else:",
                "        raise",
                "else:",
                "    print('true')"
              ]
      output <- readProcess "python3" ["-c", script, runtimeHost paths <> ":30011", bucketName, objectKey] ""
      pure (output == "true\n")

trim :: String -> String
trim = reverse . dropWhile (== '\n') . dropWhile (== ' ') . reverse . dropWhile (== ' ')

extractJsonStringField :: String -> String -> Maybe String
extractJsonStringField fieldName payload =
  case dropWhile (not . isPrefixOf marker) (tails payload) of
    candidate : _ -> Just (takeWhile (/= '"') (drop (length marker) candidate))
    [] -> Nothing
  where
    marker = "\"" <> fieldName <> "\": \""

extractJsonNullableStringField :: String -> String -> IO (Maybe String)
extractJsonNullableStringField fieldName payload
  | ("\"" <> fieldName <> "\": null") `isInfixOf` payload = pure Nothing
  | otherwise = fmap Just (requireJsonStringField fieldName payload)

requireJsonStringField :: String -> String -> IO String
requireJsonStringField fieldName payload =
  case extractJsonStringField fieldName payload of
    Just value -> pure value
    Nothing -> fail ("response JSON did not contain a string field named " <> fieldName)
