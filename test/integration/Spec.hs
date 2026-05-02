{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (SomeException, displayException, finally, try)
import Control.Monad (forM_, when)
import Data.ByteString.Lazy qualified as Lazy
import Data.Char (isAsciiUpper)
import Data.List (find, isInfixOf, isPrefixOf, isSuffixOf, stripPrefix)
import Data.Map.Strict qualified as Map
import Data.Set qualified as Set
import Data.Text qualified as Text
import Infernix.Cluster
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.DemoConfig (decodeDemoConfigFile)
import Infernix.Models
  ( catalogForMode,
    encodeDemoConfig,
    engineBindingsForMode,
    requestTopicsForMode,
    resultTopicForMode,
  )
import Infernix.Runtime.Pulsar
  ( publishInferenceRequest,
    readPublishedInferenceResultMaybe,
    schemaMarkerPath,
  )
import Infernix.Types
import System.Directory
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hFlush, stdout)
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process
  ( CreateProcess (cwd),
    createProcess,
    proc,
    readProcess,
    readProcessWithExitCode,
    terminateProcess,
    waitForProcess,
  )

main :: IO ()
main = do
  integrationTestRoot <- testRootPath "integration"
  withTestRoot integrationTestRoot $ do
    paths <- Config.discoverPaths
    runtimeModes <- integrationRuntimeModes
    mapM_ (exerciseRuntimeMode paths) runtimeModes
    when (LinuxCpu `elem` runtimeModes) $ do
      validateDemoUiDisabled paths LinuxCpu
      if Config.controlPlaneContext paths == "outer-container"
        then pure ()
        else validateEdgePortConflictAndRediscovery paths LinuxCpu
    putStrLn "integration tests passed"

integrationRuntimeModes :: IO [RuntimeMode]
integrationRuntimeModes =
  (: []) <$> Config.resolveRuntimeMode Nothing

exerciseRuntimeMode :: Paths -> RuntimeMode -> IO ()
exerciseRuntimeMode paths runtimeMode = do
  clusterUp (Just runtimeMode)
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
  assert (clusterPresent state) ("cluster up records cluster presence for " <> showRuntimeMode runtimeMode)
  let baseUrl = routeBaseUrl paths state
  reportStep ("route probes: " <> showRuntimeMode runtimeMode)
  homeResponse <- httpGet (baseUrl <> "/")
  publicationResponse <- httpGet (baseUrl <> "/api/publication")
  demoConfigResponse <- httpGet (baseUrl <> "/api/demo-config")
  modelsResponse <- httpGet (baseUrl <> "/api/models")
  harborResponse <- httpGet (baseUrl <> "/harbor")
  (harborApiStatus, harborApiResponse) <- httpGetWithStatus (baseUrl <> "/harbor/api/v2.0/projects")
  minioConsoleResponse <- httpGet (baseUrl <> "/minio/console/browser")
  (minioS3Status, minioS3Response) <- httpGetWithStatus (baseUrl <> "/minio/s3/models/demo.bin")
  pulsarAdminResponse <- httpGet (baseUrl <> "/pulsar/admin/admin/v2/clusters")
  (pulsarHttpStatus, pulsarHttpResponse) <- httpGetWithStatus (baseUrl <> "/pulsar/ws/v2/producer/public/default/demo")
  assert ("Infernix" `isInfixOf` homeResponse) "demo root serves the browser entrypoint"
  assert (("\"runtimeMode\": \"" <> showRuntimeMode runtimeMode <> "\"") `isInfixOf` publicationResponse) "publication reports the active runtime mode"
  assert ("\"clusterpresent\": true" `isInfixOf` mapToLowerAscii publicationResponse) "publication reports cluster presence"
  assert ("\"demo_ui\":true" `isInfixOf` compact demoConfigResponse) "demo config reports the enabled demo UI flag"
  assert
    ( ("\"request_topics\":[\"persistent://public/default/inference.request." <> showRuntimeMode runtimeMode <> "\"]")
        `isInfixOf` compact demoConfigResponse
    )
    "demo config reports the active request topic"
  assert
    ( ("\"result_topic\":\"persistent://public/default/inference.result." <> showRuntimeMode runtimeMode <> "\"")
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
    ( harborApiStatus == 200
        && ( "\"rewrittenPath\":\"/api/v2.0/projects\"" `isInfixOf` compact harborApiResponse
               || "\"name\":\"library\"" `isInfixOf` compact harborApiResponse
           )
    )
    "harbor API routes strip the /harbor prefix and reach the live Harbor project API on the cluster path"
  assert
    ( "\"rewrittenPath\":\"/browser\"" `isInfixOf` compact minioConsoleResponse
        || "MinIO Console" `isInfixOf` minioConsoleResponse
    )
    "minio console routes strip the /minio/console prefix and reach the live MinIO console on the cluster path"
  assert
    ( minioS3Status `elem` [200, 401, 403]
        && ( minioS3Status /= 200
               || "\"rewrittenPath\":\"/models/demo.bin\"" `isInfixOf` compact minioS3Response
           )
    )
    "minio S3 route stays published and preserves the simulated rewrite contract when it returns a 200 response"
  assert
    ( "[\"infernix-infernix-pulsar\"]" `isInfixOf` compact pulsarAdminResponse
        || "\"rewrittenPath\":\"/admin/v2/clusters\"" `isInfixOf` compact pulsarAdminResponse
    )
    "pulsar admin routes preserve the upstream admin/v2 context root"
  assert
    ( pulsarHttpStatus `elem` [200, 405]
        && ( pulsarHttpStatus /= 200
               || "\"rewrittenPath\":\"/ws/v2/producer/public/default/demo\"" `isInfixOf` compact pulsarHttpResponse
           )
    )
    "pulsar HTTP routes preserve the websocket context root and reach the real servlet on the cluster path"
  reportStep ("per-model inference: " <> showRuntimeMode runtimeMode)
  forM_ activeModelIds (validateCatalogModelInference baseUrl)
  reportStep ("cache lifecycle: " <> showRuntimeMode runtimeMode)
  cacheResponse <- httpGet (baseUrl <> "/api/cache")
  assert
    (all (\modelIdValue -> ("\"modelId\":\"" <> modelIdValue <> "\"") `isInfixOf` compact cacheResponse) activeModelIds)
    "cache status reports every materialized generated catalog entry"
  evictResponse <- httpPostJson (baseUrl <> "/api/cache/evict") ("{\"modelId\":\"" <> representativeModelId <> "\"}")
  assert ("\"evictedCount\":1" `isInfixOf` compact evictResponse) "cache eviction reports one removed entry"
  rebuildResponse <- httpPostJson (baseUrl <> "/api/cache/rebuild") ("{\"modelId\":\"" <> representativeModelId <> "\"}")
  assert ("\"rebuiltCount\":1" `isInfixOf` compact rebuildResponse) "cache rebuild reports one restored entry"

  reportStep ("service runtime loop: " <> showRuntimeMode runtimeMode)
  validateServiceRuntimeLoop paths runtimeMode representativeModelId

  when (runtimeMode == LinuxCpu) $ do
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

  statusOutput <- captureInfernixOutput ["cluster", "status"]
  assert ("clusterPresent: True" `isInfixOf` statusOutput) "cluster status reports the cluster presence"
  assert (("runtimeMode: " <> showRuntimeMode runtimeMode) `isInfixOf` statusOutput) "cluster status reports the runtime mode"
  assert ("publicationStatePath: " `isInfixOf` statusOutput) "cluster status reports the publication state path"

  clusterDown (Just runtimeMode)
  maybeDownState <- loadClusterState paths
  assert (maybe False (not . clusterPresent) maybeDownState) "cluster down records cluster absence"
  downStatusOutput <- captureInfernixOutput ["cluster", "status"]
  assert ("clusterPresent: False" `isInfixOf` downStatusOutput) "cluster status reports cluster absence after down"

validateCatalogModelInference :: String -> String -> IO ()
validateCatalogModelInference baseUrl modelIdValue = do
  inferenceResponse <-
    httpPostJson
      (baseUrl <> "/api/inference")
      ("{\"requestModelId\":\"" <> modelIdValue <> "\",\"inputText\":\"integration coverage for " <> modelIdValue <> "\"}")
  assert
    (("\"resultModelId\":\"" <> modelIdValue <> "\"") `isInfixOf` compact inferenceResponse)
    ("inference returns the selected model id for " <> modelIdValue)
  requestIdValue <- requireJsonStringField "requestId" inferenceResponse
  storedResult <- httpGet (baseUrl <> "/api/inference/" <> requestIdValue)
  assert
    (("\"requestId\":\"" <> requestIdValue <> "\"") `isInfixOf` compact storedResult)
    ("stored results can be reloaded for " <> modelIdValue)

validateServiceRuntimeLoop :: Paths -> RuntimeMode -> String -> IO ()
validateServiceRuntimeLoop paths runtimeMode representativeModelId = do
  infernixExecutable <- resolveInfernixExecutable
  requestTopic <-
    case requestTopicsForMode runtimeMode of
      topic : _ -> pure topic
      [] -> fail ("no request topics configured for " <> showRuntimeMode runtimeMode)
  let resultTopic = resultTopicForMode runtimeMode
  (_, _, _, processHandle) <-
    createProcess
      (proc infernixExecutable ["service"])
        { cwd = Just (repoRoot paths)
        }
  waitForFile (schemaMarkerPath paths requestTopic)
  waitForFile (schemaMarkerPath paths resultTopic)
  _ <-
    publishInferenceRequest
      paths
      runtimeMode
      requestTopic
      InferenceRequest
        { requestModelId = Text.pack representativeModelId,
          inputText = "service daemon request path"
        }
  maybeResult <- waitForPublishedResult paths resultTopic representativeModelId
  case maybeResult of
    Nothing -> fail ("service daemon did not publish a result for " <> showRuntimeMode runtimeMode)
    Just resultValue -> do
      assert (resultModelId resultValue == Text.pack representativeModelId) "service daemon publishes the selected model id"
      assert (resultRuntimeMode resultValue == runtimeMode) "service daemon preserves the runtime mode in published results"
  terminateProcess processHandle
  _ <- waitForProcess processHandle
  pure ()

waitForPublishedResult :: Paths -> Text.Text -> String -> IO (Maybe InferenceResult)
waitForPublishedResult paths resultTopic modelIdValue = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure Nothing
      | otherwise = do
          maybeResult <- readPublishedInferenceResultMaybe paths resultTopic (Text.pack modelIdValue <> "-request")
          case maybeResult of
            Just resultValue -> pure (Just resultValue)
            Nothing -> do
              threadDelay 100000
              go (remainingAttempts - 1)

waitForFile :: FilePath -> IO ()
waitForFile filePath = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = fail ("timed out waiting for " <> filePath)
      | otherwise = do
          exists <- doesFileExist filePath
          if exists
            then pure ()
            else do
              threadDelay 100000
              go (remainingAttempts - 1)

validateEdgePortConflictAndRediscovery :: Paths -> RuntimeMode -> IO ()
validateEdgePortConflictAndRediscovery paths runtimeMode = do
  cleanupRuntimeState paths
  (_, _, _, busyPortProcess) <-
    createProcess
      (proc "python3" ["-c", busyPortScript])
  waitForPortConflictHelper
  clusterUp (Just runtimeMode)
  busyState <- maybe (fail "cluster state was not available after busy-port cluster up") pure =<< loadClusterState paths
  assert (edgePort busyState > 9090) "cluster up chooses a non-9090 port when 9090 is busy"
  clusterDown (Just runtimeMode)
  terminateProcess busyPortProcess
  _ <- waitForProcess busyPortProcess
  clusterUp (Just runtimeMode)
  maybeRediscoveredState <- loadClusterState paths
  assert (maybe False ((== edgePort busyState) . edgePort) maybeRediscoveredState) "cluster up reuses the published edge port after restart"
  clusterDown (Just runtimeMode)
  where
    busyPortScript =
      unlines
        [ "import socket",
          "import time",
          "sock = socket.socket()",
          "sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)",
          "sock.bind(('127.0.0.1', 9090))",
          "sock.listen(1)",
          "time.sleep(30)"
        ]
    waitForPortConflictHelper = do
      threadDelay 250000

validateDemoUiDisabled :: Paths -> RuntimeMode -> IO ()
validateDemoUiDisabled paths runtimeMode = do
  cleanupRuntimeState paths
  writeGeneratedDemoConfig paths runtimeMode False
  clusterUp (Just runtimeMode)
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
  (pulsarHttpStatus, pulsarHttpResponse) <- httpGetWithStatus (baseUrl <> "/pulsar/ws/v2/producer/public/default/demo")
  assert (either (const True) (const False) disabledHomeResult) "the browser root is absent when demo_ui is disabled"
  assert (either (const True) (const False) disabledPublicationResult) "the demo API is absent when demo_ui is disabled"
  assert ("Harbor" `isInfixOf` harborResponse) "harbor remains published when demo_ui is disabled"
  assert
    ( minioS3Status `elem` [200, 401, 403]
        && ( minioS3Status /= 200
               || "\"rewrittenPath\":\"/models/demo.bin\"" `isInfixOf` compact minioS3Response
           )
    )
    "minio remains published when demo_ui is disabled"
  assert
    ( "[\"infernix-infernix-pulsar\"]" `isInfixOf` compact pulsarAdminResponse
        || "\"rewrittenPath\":\"/admin/v2/clusters\"" `isInfixOf` compact pulsarAdminResponse
    )
    "pulsar admin remains published when demo_ui is disabled"
  assert
    ( pulsarHttpStatus `elem` [200, 405]
        && ( pulsarHttpStatus /= 200
               || "\"rewrittenPath\":\"/ws/v2/producer/public/default/demo\"" `isInfixOf` compact pulsarHttpResponse
           )
    )
    "pulsar websocket route remains published when demo_ui is disabled"
  clusterDown (Just runtimeMode)
  writeGeneratedDemoConfig paths runtimeMode True

withOptionalEnv :: String -> Maybe String -> IO a -> IO a
withOptionalEnv name maybeValue action = do
  previousValue <- lookupEnv name
  applyMaybeValue maybeValue
  action
    `finally` applyMaybeValue previousValue
  where
    applyMaybeValue (Just value) = setEnv name value
    applyMaybeValue Nothing = unsetEnv name

resolveInfernixExecutable :: IO FilePath
resolveInfernixExecutable = do
  buildDir <- Config.resolveCabalBuildDir
  trimTrailingWhitespace <$> readProcess "cabal" ["--builddir=" <> buildDir, "list-bin", "exe:infernix"] ""

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
  buildDir <- Config.resolveCabalBuildDir
  (exitCode, stdoutOutput, stderrOutput) <-
    readProcessWithExitCode
      "cabal"
      ( [ "--builddir=" <> buildDir,
          "run",
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

httpPostJson :: String -> String -> IO String
httpPostJson url body =
  readProcessWithTransientCurlRetry
    ["-fsS", "-X", "POST", "-H", "Content-Type: application/json", "-d", body, url]

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

requireJsonStringField :: String -> String -> IO String
requireJsonStringField fieldName payload =
  case extractJsonStringField fieldName payload of
    Just value -> pure value
    Nothing -> fail ("missing JSON field " <> fieldName <> " in " <> payload)

extractJsonStringField :: String -> String -> Maybe String
extractJsonStringField fieldName payload =
  let needle = "\"" <> fieldName <> "\":\""
   in case breakOn needle (compact payload) of
        Just suffix -> Just (takeWhile (/= '"') suffix)
        Nothing -> Nothing

compact :: String -> String
compact = filter (`notElem` [' ', '\n', '\r', '\t'])

routeBaseUrl :: Paths -> ClusterState -> String
routeBaseUrl paths state =
  let (hostName, portNumber) = routeProbeHostAndPort paths state
   in "http://" <> hostName <> ":" <> show portNumber

routeProbeHostAndPort :: Paths -> ClusterState -> (String, Int)
routeProbeHostAndPort paths state
  | Config.controlPlaneContext paths == "outer-container" =
      (kindControlPlaneNodeName paths (clusterRuntimeMode state), 30090)
  | otherwise = ("127.0.0.1", edgePort state)

breakOn :: String -> String -> Maybe String
breakOn needle = go
  where
    go [] = Nothing
    go value
      | needle `isPrefixOf` value = Just (drop (length needle) value)
      | otherwise = go (drop 1 value)

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
  previousDataRoot <- lookupEnv "INFERNIX_DATA_ROOT"
  setEnv "INFERNIX_DATA_ROOT" (root </> ".data")
  withCurrentDirectory root action
    `finally` maybe (unsetEnv "INFERNIX_DATA_ROOT") (setEnv "INFERNIX_DATA_ROOT") previousDataRoot
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

writeGeneratedDemoConfig :: Paths -> RuntimeMode -> Bool -> IO ()
writeGeneratedDemoConfig paths runtimeMode demoUiEnabledValue = do
  createDirectoryIfMissing True (buildRoot paths)
  Lazy.writeFile
    (Config.generatedDemoConfigPath paths runtimeMode)
    ( encodeDemoConfig
        DemoConfig
          { configRuntimeMode = runtimeMode,
            configEdgePort = 0,
            configMapName = "infernix-demo-config",
            generatedPath = Config.generatedDemoConfigPath paths runtimeMode,
            mountedPath = Config.watchedDemoConfigPath runtimeMode,
            demoUiEnabled = demoUiEnabledValue,
            requestTopics = requestTopicsForMode runtimeMode,
            resultTopic = resultTopicForMode runtimeMode,
            engines = engineBindingsForMode runtimeMode,
            models = catalogForMode runtimeMode
          }
    )

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
          "infernix-service",
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
  mountPath <-
    trim
      <$> kubectlOutputForState
        state
        [ "-n",
          "platform",
          "get",
          "pod",
          "infernix-minio-0",
          "-o",
          "jsonpath={.spec.containers[0].volumeMounts[?(@.name==\"data\")].mountPath}"
        ]
  assert (not (null mountPath)) "minio data volume mount path is discoverable"
  let sentinelPath = mountPath <> "/ha-smoke/minio-sentinel.txt"
  runKubectl state ["-n", "platform", "exec", "infernix-minio-0", "--", "sh", "-lc", "mkdir -p " <> mountPath <> "/ha-smoke && printf minio-durable > " <> sentinelPath]
  runKubectl state ["-n", "platform", "delete", "pod", "infernix-minio-0"]
  waitForPodReady state "platform" "infernix-minio-0"
  sentinelContents <- trim <$> kubectlOutputForState state ["-n", "platform", "exec", "infernix-minio-0", "--", "sh", "-lc", "cat " <> sentinelPath]
  assert (sentinelContents == "minio-durable") "minio data written before pod replacement remains available afterward"

validateRoutedPulsarRecovery :: Paths -> ClusterState -> RuntimeMode -> [String] -> IO ()
validateRoutedPulsarRecovery paths state runtimeMode activeModelIds =
  case activeModelIds of
    firstModelId : secondModelId : _ -> do
      let baseUrl = routeBaseUrl paths state
      withPulsarTransportEnv baseUrl $ do
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
  _ <-
    publishInferenceRequest
      paths
      runtimeMode
      requestTopic
      InferenceRequest
        { requestModelId = Text.pack modelIdValue,
          inputText = Text.pack inputValue
        }
  maybeResult <- waitForPublishedResult paths resultTopic modelIdValue
  case maybeResult of
    Nothing -> fail ("pulsar roundtrip did not publish a result for " <> modelIdValue)
    Just resultValue ->
      assert (resultModelId resultValue == Text.pack modelIdValue) ("pulsar roundtrip preserves the selected model id for " <> modelIdValue)

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

withPulsarTransportEnv :: String -> IO a -> IO a
withPulsarTransportEnv baseUrl action = do
  transportBaseUrl <- resolvePulsarTransportBaseUrl baseUrl
  withOptionalEnv "INFERNIX_PULSAR_ADMIN_URL" (Just (transportBaseUrl <> "/pulsar/admin/admin/v2")) $
    withOptionalEnv "INFERNIX_PULSAR_WS_BASE_URL" (Just (toWebSocketBaseUrl transportBaseUrl <> "/pulsar/ws/v2")) action

resolvePulsarTransportBaseUrl :: String -> IO String
resolvePulsarTransportBaseUrl baseUrl =
  case splitHttpUrl baseUrl of
    Just ("http://", hostName, portAndPath)
      | "-control-plane" `isSuffixOf` hostName -> do
          resolvedHost <- trimTrailingWhitespace <$> readProcess "docker" ["inspect", "-f", "{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}", hostName] ""
          pure
            ( if null resolvedHost
                then baseUrl
                else "http://" <> resolvedHost <> portAndPath
            )
    _ -> pure baseUrl

splitHttpUrl :: String -> Maybe (String, String, String)
splitHttpUrl url =
  case parseScheme "http://" of
    Just parsed -> Just parsed
    Nothing -> parseScheme "https://"
  where
    parseScheme scheme = do
      suffix <- stripPrefix scheme url
      let (hostName, portAndPath) = break (`elem` [':', '/']) suffix
      if null hostName
        then Nothing
        else Just (scheme, hostName, portAndPath)

toWebSocketBaseUrl :: String -> String
toWebSocketBaseUrl baseUrl =
  case breakOn "http://" baseUrl of
    Just suffix -> "ws://" <> suffix
    Nothing ->
      case breakOn "https://" baseUrl of
        Just suffix -> "wss://" <> suffix
        Nothing -> baseUrl

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
