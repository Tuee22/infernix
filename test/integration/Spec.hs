{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (finally, try)
import Control.Monad (when)
import Data.Char (isAsciiUpper)
import Data.List (isInfixOf, isPrefixOf)
import Data.Text qualified as Text
import Infernix.Cluster
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.Models (requestTopicsForMode, resultTopicForMode)
import Infernix.Runtime.Pulsar
  ( publishInferenceRequest,
    readPublishedInferenceResultMaybe,
    schemaMarkerPath,
  )
import Infernix.Types
import Infernix.Workflow (platformCommandsAvailable)
import System.Directory
import System.Environment (lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
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
integrationRuntimeModes = do
  maybeRuntimeModeValue <- lookupEnv "INFERNIX_RUNTIME_MODE"
  case maybeRuntimeModeValue of
    Nothing -> pure [AppleSilicon, LinuxCpu, LinuxCuda]
    Just rawValue ->
      case parseRuntimeMode (Text.pack rawValue) of
        Just runtimeMode -> pure [runtimeMode]
        Nothing -> fail ("unsupported INFERNIX_RUNTIME_MODE for integration tests: " <> rawValue)

exerciseRuntimeMode :: Paths -> RuntimeMode -> IO ()
exerciseRuntimeMode paths runtimeMode = do
  commandsAvailable <- platformCommandsAvailable
  clusterUp (Just runtimeMode)
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available after cluster up") pure maybeState
  assert (clusterPresent state) ("cluster up records cluster presence for " <> showRuntimeMode runtimeMode)
  assert
    (clusterSimulation state == not commandsAvailable)
    ("cluster up reports the expected substrate mode for " <> showRuntimeMode runtimeMode)
  let baseUrl = routeBaseUrl paths state
  homeResponse <- httpGet (baseUrl <> "/")
  publicationResponse <- httpGet (baseUrl <> "/api/publication")
  demoConfigResponse <- httpGet (baseUrl <> "/api/demo-config")
  modelsResponse <- httpGet (baseUrl <> "/api/models")
  harborResponse <- httpGet (baseUrl <> "/harbor")
  harborApiResponse <- httpGet (baseUrl <> "/harbor/api/v2.0/projects")
  minioConsoleResponse <- httpGet (baseUrl <> "/minio/console/browser")
  minioS3Response <- httpGet (baseUrl <> "/minio/s3/models/demo.bin")
  pulsarAdminResponse <- httpGet (baseUrl <> "/pulsar/admin/clusters")
  pulsarHttpResponse <- httpGet (baseUrl <> "/pulsar/ws/v2/producer/public/default/demo")
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
  assert ("Harbor" `isInfixOf` harborResponse) "harbor route is published"
  assert ("\"rewrittenPath\":\"/api/v2.0/projects\"" `isInfixOf` compact harborApiResponse) "harbor API routes strip the /harbor prefix"
  assert ("\"rewrittenPath\":\"/browser\"" `isInfixOf` compact minioConsoleResponse) "minio console routes strip the /minio/console prefix"
  assert ("\"rewrittenPath\":\"/models/demo.bin\"" `isInfixOf` compact minioS3Response) "minio S3 routes strip the /minio/s3 prefix"
  assert ("\"rewrittenPath\":\"/clusters\"" `isInfixOf` compact pulsarAdminResponse) "pulsar admin routes strip the /pulsar/admin prefix"
  assert ("\"rewrittenPath\":\"/ws/v2/producer/public/default/demo\"" `isInfixOf` compact pulsarHttpResponse) "pulsar HTTP routes preserve the Pulsar websocket context root"

  inferenceResponse <-
    httpPostJson
      (baseUrl <> "/api/inference")
      "{\"requestModelId\":\"llm-qwen25-safetensors\",\"inputText\":\"integration coverage for the simulated platform\"}"
  assert ("\"resultModelId\":\"llm-qwen25-safetensors\"" `isInfixOf` compact inferenceResponse) "inference returns the selected model id"
  requestIdValue <- requireJsonStringField "requestId" inferenceResponse
  storedResult <- httpGet (baseUrl <> "/api/inference/" <> requestIdValue)
  assert
    (("\"requestId\":\"" <> requestIdValue <> "\"") `isInfixOf` compact storedResult)
    ("stored results can be reloaded for " <> showRuntimeMode runtimeMode)
  cacheResponse <- httpGet (baseUrl <> "/api/cache")
  assert ("\"modelId\":\"llm-qwen25-safetensors\"" `isInfixOf` compact cacheResponse) "cache status reports the materialized model"
  evictResponse <- httpPostJson (baseUrl <> "/api/cache/evict") "{\"modelId\":\"llm-qwen25-safetensors\"}"
  assert ("\"evictedCount\":1" `isInfixOf` compact evictResponse) "cache eviction reports one removed entry"
  rebuildResponse <- httpPostJson (baseUrl <> "/api/cache/rebuild") "{\"modelId\":\"llm-qwen25-safetensors\"}"
  assert ("\"rebuiltCount\":1" `isInfixOf` compact rebuildResponse) "cache rebuild reports one restored entry"

  validateServiceRuntimeLoop paths runtimeMode

  statusOutput <- captureInfernixOutput paths runtimeMode ["cluster", "status"]
  assert ("clusterPresent: True" `isInfixOf` statusOutput) "cluster status reports the cluster presence"
  assert (("runtimeMode: " <> showRuntimeMode runtimeMode) `isInfixOf` statusOutput) "cluster status reports the runtime mode"
  assert ("publicationStatePath: " `isInfixOf` statusOutput) "cluster status reports the publication state path"

  clusterDown (Just runtimeMode)
  maybeDownState <- loadClusterState paths
  assert (maybe False (not . clusterPresent) maybeDownState) "cluster down records cluster absence"
  downStatusOutput <- captureInfernixOutput paths runtimeMode ["cluster", "status"]
  assert ("clusterPresent: False" `isInfixOf` downStatusOutput) "cluster status reports cluster absence after down"

validateServiceRuntimeLoop :: Paths -> RuntimeMode -> IO ()
validateServiceRuntimeLoop paths runtimeMode = do
  infernixExecutable <- resolveInfernixExecutable
  requestTopic <-
    case requestTopicsForMode runtimeMode of
      topic : _ -> pure topic
      [] -> fail ("no request topics configured for " <> showRuntimeMode runtimeMode)
  let resultTopic = resultTopicForMode runtimeMode
  (_, _, _, processHandle) <-
    createProcess
      (proc infernixExecutable ["--runtime-mode", showRuntimeMode runtimeMode, "service"])
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
        { requestModelId = "llm-qwen25-safetensors",
          inputText = "service daemon request path"
        }
  maybeResult <- waitForPublishedResult paths resultTopic
  case maybeResult of
    Nothing -> fail ("service daemon did not publish a result for " <> showRuntimeMode runtimeMode)
    Just resultValue -> do
      assert (resultModelId resultValue == "llm-qwen25-safetensors") "service daemon publishes the selected model id"
      assert (resultRuntimeMode resultValue == runtimeMode) "service daemon preserves the runtime mode in published results"
  terminateProcess processHandle
  _ <- waitForProcess processHandle
  pure ()

waitForPublishedResult :: Paths -> Text.Text -> IO (Maybe InferenceResult)
waitForPublishedResult paths resultTopic = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure Nothing
      | otherwise = do
          maybeResult <- readPublishedInferenceResultMaybe paths resultTopic "llm-qwen25-safetensors-request"
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
validateDemoUiDisabled paths runtimeMode =
  withOptionalEnv "INFERNIX_DEMO_UI" (Just "false") $ do
    cleanupRuntimeState paths
    clusterUp (Just runtimeMode)
    state <- maybe (fail "cluster state was not available after demo-disabled cluster up") pure =<< loadClusterState paths
    assert (clusterPresent state) "cluster up records cluster presence when demo_ui is disabled"
    assert (not (any ((== "/") . path) (routes state))) "route inventory omits the browser root when demo_ui is disabled"
    assert (not (any ((== "/api") . path) (routes state))) "route inventory omits the demo API when demo_ui is disabled"
    let baseUrl = routeBaseUrl paths state
    disabledHomeResult <- try (httpGet (baseUrl <> "/")) :: IO (Either IOError String)
    disabledPublicationResult <- try (httpGet (baseUrl <> "/api/publication")) :: IO (Either IOError String)
    harborResponse <- httpGet (baseUrl <> "/harbor")
    minioResponse <- httpGet (baseUrl <> "/minio/s3")
    pulsarResponse <- httpGet (baseUrl <> "/pulsar/ws")
    assert (either (const True) (const False) disabledHomeResult) "the browser root is absent when demo_ui is disabled"
    assert (either (const True) (const False) disabledPublicationResult) "the demo API is absent when demo_ui is disabled"
    assert ("Harbor" `isInfixOf` harborResponse) "harbor remains published when demo_ui is disabled"
    assert ("\"status\":\"ready\"" `isInfixOf` compact minioResponse) "minio remains published when demo_ui is disabled"
    assert ("\"brokersHealth\":\"ready\"" `isInfixOf` compact pulsarResponse) "pulsar remains published when demo_ui is disabled"
    clusterDown (Just runtimeMode)

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

cleanupRuntimeState :: Paths -> IO ()
cleanupRuntimeState paths = do
  catchIOError (removePathForcibly (runtimeRoot paths)) ignoreMissing
  createDirectoryIfMissing True (runtimeRoot paths)
  where
    ignoreMissing err
      | isDoesNotExistError err = pure ()
      | otherwise = ioError err

captureInfernixOutput :: Paths -> RuntimeMode -> [String] -> IO String
captureInfernixOutput _ runtimeMode args = do
  buildDir <- Config.resolveCabalBuildDir
  (exitCode, stdoutOutput, stderrOutput) <-
    readProcessWithExitCode
      "cabal"
      ( [ "--builddir=" <> buildDir,
          "run",
          "exe:infernix",
          "--",
          "--runtime-mode",
          showRuntimeMode runtimeMode
        ]
          <> args
      )
      ""
  assert (exitCode == ExitSuccess) ("infernix command succeeded: " <> stderrOutput)
  pure stdoutOutput

httpGet :: String -> IO String
httpGet url = readProcess "curl" ["-fsS", url] ""

httpPostJson :: String -> String -> IO String
httpPostJson url body =
  readProcess
    "curl"
    ["-fsS", "-X", "POST", "-H", "Content-Type: application/json", "-d", body, url]
    ""

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
  | clusterSimulation state = ("127.0.0.1", edgePort state)
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
