{-# LANGUAGE OverloadedStrings #-}

module Main (main) where

import Control.Concurrent (threadDelay)
import Control.Exception (finally, try)
import Data.Char (isAsciiUpper)
import Data.List (isInfixOf, isPrefixOf)
import Data.Text qualified as Text
import Infernix.Cluster
import Infernix.Config (Paths (..))
import Infernix.Config qualified as Config
import Infernix.Types
import System.Directory
import System.Environment (getEnvironment, lookupEnv, setEnv, unsetEnv)
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath ((</>))
import System.IO (hClose, hGetLine)
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Process
  ( CreateProcess (cwd, env, std_err, std_in, std_out),
    StdStream (CreatePipe),
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
    mapM_ (exerciseRuntimeMode paths) [AppleSilicon, LinuxCpu, LinuxCuda]
    validateDemoUiDisabled paths LinuxCpu
    validateEdgePortConflictAndRediscovery paths LinuxCpu
    validateStandaloneProxyProcesses paths
    putStrLn "integration tests passed"

exerciseRuntimeMode :: Paths -> RuntimeMode -> IO ()
exerciseRuntimeMode paths runtimeMode = do
  clusterUp (Just runtimeMode)
  maybeState <- loadClusterState paths
  state <- maybe (fail "cluster state was not available after cluster up") pure maybeState
  assert (clusterPresent state) ("cluster up records cluster presence for " <> showRuntimeMode runtimeMode)
  assert (clusterSimulation state) ("cluster up uses the simulated substrate for " <> showRuntimeMode runtimeMode)
  let baseUrl = "http://127.0.0.1:" <> show (edgePort state)
  homeResponse <- httpGet (baseUrl <> "/")
  publicationResponse <- httpGet (baseUrl <> "/api/publication")
  demoConfigResponse <- httpGet (baseUrl <> "/api/demo-config")
  modelsResponse <- httpGet (baseUrl <> "/api/models")
  harborResponse <- httpGet (baseUrl <> "/harbor")
  minioResponse <- httpGet (baseUrl <> "/minio/s3")
  pulsarResponse <- httpGet (baseUrl <> "/pulsar/ws")
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
  assert ("\"adapterId\":\"" `isInfixOf` compact demoConfigResponse) "demo config publishes adapter ids for engine bindings"
  assert ("\"modelId\"" `isInfixOf` modelsResponse) "model listing returns JSON models"
  assert ("Harbor Gateway" `isInfixOf` harborResponse) "harbor route is published"
  assert ("\"status\":\"ready\"" `isInfixOf` compact minioResponse) "minio route is published"
  assert ("\"brokersHealth\":\"ready\"" `isInfixOf` compact pulsarResponse) "pulsar route is published"

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

  statusOutput <- captureInfernixOutput paths runtimeMode ["cluster", "status"]
  assert ("clusterPresent: True" `isInfixOf` statusOutput) "cluster status reports the cluster presence"
  assert (("runtimeMode: " <> showRuntimeMode runtimeMode) `isInfixOf` statusOutput) "cluster status reports the runtime mode"
  assert ("publicationStatePath: " `isInfixOf` statusOutput) "cluster status reports the publication state path"

  clusterDown (Just runtimeMode)
  maybeDownState <- loadClusterState paths
  assert (maybe False (not . clusterPresent) maybeDownState) "cluster down records cluster absence"
  downStatusOutput <- captureInfernixOutput paths runtimeMode ["cluster", "status"]
  assert ("clusterPresent: False" `isInfixOf` downStatusOutput) "cluster status reports cluster absence after down"

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
      readyLine <- hGetLine stdoutHandle
      assert (readyLine == "ready") "busy-port helper binds 9090 before cluster up runs"
      clusterUp (Just runtimeMode)
      busyState <- maybe (fail "cluster state was not available after busy-port cluster up") pure =<< loadClusterState paths
      assert (edgePort busyState > 9090) "cluster up chooses a non-9090 port when 9090 is busy"
      clusterDown (Just runtimeMode)
      hClose stdinHandle
      terminateProcess busyPortProcess
      _ <- waitForProcess busyPortProcess
      clusterUp (Just runtimeMode)
      maybeRediscoveredState <- loadClusterState paths
      assert (maybe False ((== edgePort busyState) . edgePort) maybeRediscoveredState) "cluster up reuses the published edge port after restart"
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

validateDemoUiDisabled :: Paths -> RuntimeMode -> IO ()
validateDemoUiDisabled paths runtimeMode =
  withOptionalEnv "INFERNIX_DEMO_UI" (Just "false") $ do
    cleanupRuntimeState paths
    clusterUp (Just runtimeMode)
    state <- maybe (fail "cluster state was not available after demo-disabled cluster up") pure =<< loadClusterState paths
    assert (clusterPresent state) "cluster up records cluster presence when demo_ui is disabled"
    assert (not (any ((== "/") . path) (routes state))) "route inventory omits the browser root when demo_ui is disabled"
    assert (not (any ((== "/api") . path) (routes state))) "route inventory omits the demo API when demo_ui is disabled"
    let baseUrl = "http://127.0.0.1:" <> show (edgePort state)
    disabledHomeResult <- try (httpGet (baseUrl <> "/")) :: IO (Either IOError String)
    disabledPublicationResult <- try (httpGet (baseUrl <> "/api/publication")) :: IO (Either IOError String)
    harborResponse <- httpGet (baseUrl <> "/harbor")
    minioResponse <- httpGet (baseUrl <> "/minio/s3")
    pulsarResponse <- httpGet (baseUrl <> "/pulsar/ws")
    assert (either (const True) (const False) disabledHomeResult) "the browser root is absent when demo_ui is disabled"
    assert (either (const True) (const False) disabledPublicationResult) "the demo API is absent when demo_ui is disabled"
    assert ("Harbor Gateway" `isInfixOf` harborResponse) "harbor remains published when demo_ui is disabled"
    assert ("\"status\":\"ready\"" `isInfixOf` compact minioResponse) "minio remains published when demo_ui is disabled"
    assert ("\"brokersHealth\":\"ready\"" `isInfixOf` compact pulsarResponse) "pulsar remains published when demo_ui is disabled"
    clusterDown (Just runtimeMode)

validateStandaloneProxyProcesses :: Paths -> IO ()
validateStandaloneProxyProcesses paths = do
  infernixExecutable <- resolveInfernixExecutable
  withMockServer "demo" $ \demoPort ->
    withMockServer "web" $ \webPort ->
      withMockServer "harbor-ui" $ \harborUiPort ->
        withMockServer "harbor-api" $ \harborApiPort ->
          withMockServer "minio-console" $ \minioConsolePort ->
            withMockServer "minio-s3" $ \minioS3Port ->
              withMockServer "pulsar-admin" $ \pulsarAdminPort ->
                withMockServer "pulsar-http" $ \pulsarHttpPort -> do
                  withInfernixProcess
                    paths
                    infernixExecutable
                    ["edge"]
                    19190
                    "/healthz"
                    [ ("INFERNIX_BIND_HOST", "127.0.0.1"),
                      ("INFERNIX_DEMO_UPSTREAM", "127.0.0.1:" <> show demoPort),
                      ("INFERNIX_WEB_UPSTREAM", "127.0.0.1:" <> show webPort),
                      ("INFERNIX_HARBOR_UPSTREAM", "127.0.0.1:" <> show harborUiPort),
                      ("INFERNIX_MINIO_UPSTREAM", "127.0.0.1:" <> show minioConsolePort),
                      ("INFERNIX_PULSAR_UPSTREAM", "127.0.0.1:" <> show pulsarHttpPort)
                    ]
                    $ do
                      edgeApiResponse <- httpGet "http://127.0.0.1:19190/api/models?lane=test"
                      edgeHarborResponse <- httpGet "http://127.0.0.1:19190/harbor/projects"
                      edgeMinioResponse <- httpGet "http://127.0.0.1:19190/minio/console/browser"
                      edgeHomeResponse <- httpGet "http://127.0.0.1:19190/"
                      assert ("\"label\": \"demo\"" `isInfixOf` edgeApiResponse) "edge proxy sends /api traffic to the demo upstream"
                      assert ("\"path\": \"/api/models?lane=test\"" `isInfixOf` edgeApiResponse) "edge proxy preserves the original API request path"
                      assert ("\"label\": \"harbor-ui\"" `isInfixOf` edgeHarborResponse) "edge proxy sends /harbor traffic to the Harbor upstream"
                      assert ("\"label\": \"minio-console\"" `isInfixOf` edgeMinioResponse) "edge proxy sends /minio traffic to the MinIO upstream"
                      assert ("\"label\": \"demo\"" `isInfixOf` edgeHomeResponse) "edge proxy sends the browser root to the demo upstream"

                  withInfernixProcess
                    paths
                    infernixExecutable
                    ["gateway", "harbor"]
                    19191
                    "/harbor"
                    [ ("INFERNIX_BIND_HOST", "127.0.0.1"),
                      ("INFERNIX_HARBOR_BACKEND_URL", "http://127.0.0.1:" <> show harborUiPort),
                      ("INFERNIX_HARBOR_API_URL", "http://127.0.0.1:" <> show harborApiPort),
                      ("INFERNIX_HARBOR_ADMIN_USER", "admin"),
                      ("INFERNIX_HARBOR_ADMIN_PASSWORD", "secret")
                    ]
                    $ do
                      harborRootResponse <- httpGet "http://127.0.0.1:19191/harbor"
                      harborApiResponse <- httpGet "http://127.0.0.1:19191/harbor/api/v2.0/projects"
                      assert ("\"label\": \"harbor-ui\"" `isInfixOf` harborRootResponse) "Harbor gateway proxies the portal root to the Harbor UI upstream"
                      assert ("\"label\": \"harbor-api\"" `isInfixOf` harborApiResponse) "Harbor gateway proxies API traffic to the Harbor API upstream"
                      assert ("\"path\": \"/api/v2.0/projects\"" `isInfixOf` harborApiResponse) "Harbor gateway strips the routed Harbor prefix for API requests"
                      assert ("\"authorization\": \"Basic YWRtaW46c2VjcmV0\"" `isInfixOf` harborApiResponse) "Harbor gateway injects the configured basic-auth header"

                  withInfernixProcess
                    paths
                    infernixExecutable
                    ["gateway", "minio"]
                    19192
                    "/minio/s3"
                    [ ("INFERNIX_BIND_HOST", "127.0.0.1"),
                      ("INFERNIX_MINIO_S3_ENDPOINT", "http://127.0.0.1:" <> show minioS3Port),
                      ("INFERNIX_MINIO_CONSOLE_ENDPOINT", "http://127.0.0.1:" <> show minioConsolePort)
                    ]
                    $ do
                      minioStatusResponse <- httpGet "http://127.0.0.1:19192/minio/s3"
                      minioS3Response <- httpGet "http://127.0.0.1:19192/minio/s3/models/demo.bin"
                      minioConsoleResponse <- httpGet "http://127.0.0.1:19192/minio/console/browser"
                      assert ("\"status\":\"ready\"" `isInfixOf` compact minioStatusResponse) "MinIO gateway serves the stable exact-path readiness response"
                      assert (("\"targetUrl\":\"http://127.0.0.1:" <> show minioS3Port <> "\"") `isInfixOf` compact minioStatusResponse) "MinIO gateway reports the configured S3 upstream"
                      assert ("\"label\": \"minio-s3\"" `isInfixOf` minioS3Response) "MinIO gateway proxies routed S3 traffic to the S3 upstream"
                      assert ("\"path\": \"/models/demo.bin\"" `isInfixOf` minioS3Response) "MinIO gateway strips the routed S3 prefix"
                      assert ("\"label\": \"minio-console\"" `isInfixOf` minioConsoleResponse) "MinIO gateway proxies console traffic to the console upstream"

                  withInfernixProcess
                    paths
                    infernixExecutable
                    ["gateway", "pulsar"]
                    19193
                    "/pulsar/ws"
                    [ ("INFERNIX_BIND_HOST", "127.0.0.1"),
                      ("INFERNIX_PULSAR_ADMIN_URL", "http://127.0.0.1:" <> show pulsarAdminPort),
                      ("INFERNIX_PULSAR_HTTP_BASE_URL", "http://127.0.0.1:" <> show pulsarHttpPort)
                    ]
                    $ do
                      pulsarStatusResponse <- httpGet "http://127.0.0.1:19193/pulsar/ws"
                      pulsarAdminResponse <- httpGet "http://127.0.0.1:19193/pulsar/admin/clusters"
                      pulsarHttpResponse <- httpGet "http://127.0.0.1:19193/pulsar/ws/v2/producer/public/default/demo"
                      assert ("\"brokersHealth\":\"ready\"" `isInfixOf` compact pulsarStatusResponse) "Pulsar gateway serves the stable exact-path readiness response"
                      assert ("\"label\": \"pulsar-admin\"" `isInfixOf` pulsarAdminResponse) "Pulsar gateway proxies admin traffic to the admin upstream"
                      assert ("\"path\": \"/clusters\"" `isInfixOf` pulsarAdminResponse) "Pulsar gateway strips the routed admin prefix"
                      assert ("\"label\": \"pulsar-http\"" `isInfixOf` pulsarHttpResponse) "Pulsar gateway proxies routed HTTP traffic to the broker HTTP upstream"
                      assert ("\"path\": \"/v2/producer/public/default/demo\"" `isInfixOf` pulsarHttpResponse) "Pulsar gateway strips the routed websocket prefix for HTTP requests"

withMockServer :: String -> (Int -> IO a) -> IO a
withMockServer label action = do
  (_, Just stdoutHandle, _, processHandle) <-
    createProcess
      (proc "python3" ["-c", mockServerScript, label])
        { std_out = CreatePipe
        }
  portValue <- read <$> hGetLine stdoutHandle
  action portValue
    `finally` do
      terminateProcess processHandle
      _ <- waitForProcess processHandle
      hClose stdoutHandle
      pure ()

withInfernixProcess :: Paths -> FilePath -> [String] -> Int -> String -> [(String, String)] -> IO a -> IO a
withInfernixProcess paths executablePath args portValue readyPath envOverrides action = do
  baseEnvironment <- getEnvironment
  (_, _, _, processHandle) <-
    createProcess
      (proc executablePath args)
        { cwd = Just (repoRoot paths),
          env =
            Just
              ( mergeEnvironment
                  [("INFERNIX_PORT", show portValue)]
                  (mergeEnvironment envOverrides baseEnvironment)
              )
        }
  waitForHttpReady ("http://127.0.0.1:" <> show portValue <> readyPath)
  action
    `finally` do
      terminateProcess processHandle
      _ <- waitForProcess processHandle
      pure ()

withOptionalEnv :: String -> Maybe String -> IO a -> IO a
withOptionalEnv name maybeValue action = do
  previousValue <- lookupEnv name
  applyMaybeValue maybeValue
  action
    `finally` applyMaybeValue previousValue
  where
    applyMaybeValue (Just value) = setEnv name value
    applyMaybeValue Nothing = unsetEnv name

waitForHttpReady :: String -> IO ()
waitForHttpReady url = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = fail ("timed out waiting for " <> url)
      | otherwise = do
          result <- try (httpGet url) :: IO (Either IOError String)
          case result of
            Right _ -> pure ()
            Left _ -> do
              threadDelay 100000
              go (remainingAttempts - 1)

resolveInfernixExecutable :: IO FilePath
resolveInfernixExecutable = do
  buildDir <- Config.resolveCabalBuildDir
  trimTrailingWhitespace <$> readProcess "cabal" ["--builddir=" <> buildDir, "list-bin", "exe:infernix"] ""

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment overrides environment =
  overrides <> filter (\(name, _) -> name `notElem` map fst overrides) environment

trimTrailingWhitespace :: String -> String
trimTrailingWhitespace =
  reverse . dropWhile (`elem` [' ', '\n', '\r', '\t']) . reverse

mockServerScript :: String
mockServerScript =
  unlines
    [ "import json",
      "import sys",
      "from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer",
      "label = sys.argv[1]",
      "class Handler(BaseHTTPRequestHandler):",
      "    def do_GET(self):",
      "        payload = json.dumps({",
      "            'label': label,",
      "            'path': self.path,",
      "            'authorization': self.headers.get('Authorization', ''),",
      "        }).encode('utf-8')",
      "        self.send_response(200)",
      "        self.send_header('Content-Type', 'application/json; charset=utf-8')",
      "        self.send_header('Content-Length', str(len(payload)))",
      "        self.end_headers()",
      "        self.wfile.write(payload)",
      "    def log_message(self, format, *args):",
      "        return",
      "server = ThreadingHTTPServer(('127.0.0.1', 0), Handler)",
      "print(server.server_address[1], flush=True)",
      "server.serve_forever()"
    ]

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
