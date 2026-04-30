{-# LANGUAGE OverloadedStrings #-}

module Infernix.CLI
  ( main,
    extractRuntimeMode,
    writeGeneratedPursContracts,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, catch, evaluate, finally, try)
import Control.Monad (when)
import Data.Aeson (Value (..), eitherDecode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.Cluster
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.CommandRegistry
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile, renderModelListing, validateDemoConfigFile)
import Infernix.HostPrereqs (ensureAppleHostPrerequisites)
import Infernix.Lint.Chart (runChartLint)
import Infernix.Lint.Docs (runDocsLint)
import Infernix.Lint.Files (runFilesLint)
import Infernix.Lint.Proto (runProtoLint)
import Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectReady,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
import Infernix.Runtime (evictCache, listCacheManifests, rebuildCache)
import Infernix.Runtime.Pulsar (publishInferenceRequest, readPublishedInferenceResultMaybe)
import Infernix.Service
import Infernix.Storage (readEdgePortMaybe)
import Infernix.Types
  ( CacheManifest (..),
    DemoConfig (..),
    InferenceRequest (..),
    InferenceResult (..),
    PersistentClaim (..),
    ResultPayload (..),
    RuntimeMode (AppleSilicon, LinuxCuda),
    allRuntimeModes,
    parseRuntimeMode,
    runtimeModeId,
  )
import Infernix.Web.Contracts qualified as Contracts
import Infernix.Workflow
  ( ensurePlaywrightBrowsers,
    ensureWebDependencies,
    platformCommandsAvailableForE2E,
    resolveWebNpmInvocation,
  )
import Language.PureScript.Bridge (buildBridge, defaultBridge, writePSTypesWith)
import Language.PureScript.Bridge.Builder (BridgePart, (^==))
import Language.PureScript.Bridge.CodeGenSwitches (noArgonautCodecs, noLenses)
import Language.PureScript.Bridge.PSTypes (psArray)
import Language.PureScript.Bridge.TypeInfo (typeName)
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    getPermissions,
    removePathForcibly,
    setPermissions,
  )
import System.Environment (getArgs, getEnvironment, getExecutablePath)
import System.Exit (ExitCode (ExitSuccess), exitFailure, exitWith)
import System.FilePath (takeFileName, (</>))
import System.Process (CreateProcess (cwd, env), createProcess, proc, readProcess, terminateProcess, waitForProcess)

main :: IO ()
main = do
  setLocaleEncoding utf8
  syncBuildRootExecutable
  args <- getArgs
  case extractRuntimeMode args of
    Left message -> do
      putStrLn message
      exitFailure
    Right (maybeRuntimeMode, remainingArgs) -> dispatch maybeRuntimeMode remainingArgs

dispatch :: Maybe RuntimeMode -> [String] -> IO ()
dispatch maybeRuntimeMode args =
  case parseCommand args of
    Left _ -> do
      putStrLn helpText
      exitFailure
    Right command -> do
      ensureAppleHostPrerequisites maybeRuntimeMode command
      case command of
        ShowRootHelp -> putStrLn helpText
        ShowTopicHelp topic -> putStrLn (topicHelpText topic)
        ServiceCommand -> runService maybeRuntimeMode
        ClusterUpCommand -> clusterUp maybeRuntimeMode
        ClusterDownCommand -> clusterDown maybeRuntimeMode
        ClusterStatusCommand -> clusterStatus maybeRuntimeMode
        CacheStatusCommand -> runCacheStatus maybeRuntimeMode
        CacheEvictCommand maybeModelId -> runCacheEvict maybeRuntimeMode (Text.pack <$> maybeModelId)
        CacheRebuildCommand maybeModelId -> runCacheRebuild maybeRuntimeMode (Text.pack <$> maybeModelId)
        KubectlCommand kubectlArgs -> runKubectlCompat kubectlArgs
        DocsCheckCommand -> runDocsLint
        LintFilesCommand -> runFilesLint
        LintDocsCommand -> runDocsLint
        LintProtoCommand -> runProtoLint
        LintChartCommand -> runChartLint
        TestLintCommand -> runLint maybeRuntimeMode
        TestUnitCommand -> do
          ensureWebDependencies
          ensurePythonAdapterDependencies maybeRuntimeMode
          runCabalCommand maybeRuntimeMode ["test", "infernix-unit"]
          runWebNpmCommand maybeRuntimeMode ["--prefix", "web", "run", "test:unit"]
        TestIntegrationCommand -> runCabalCommand maybeRuntimeMode ["test", "infernix-integration"]
        TestE2ECommand -> runEndToEnd maybeRuntimeMode
        TestAllCommand -> do
          ensureWebDependencies
          runLint maybeRuntimeMode
          ensurePythonAdapterDependencies maybeRuntimeMode
          runCabalCommand maybeRuntimeMode ["test", "infernix-unit"]
          runWebNpmCommand maybeRuntimeMode ["--prefix", "web", "run", "test:unit"]
          runCabalCommand maybeRuntimeMode ["test", "infernix-integration"]
          runEndToEnd maybeRuntimeMode
        InternalDiscoverImagesCommand renderedChartPath ->
          mapM_ putStrLn =<< discoverChartImagesFile renderedChartPath
        InternalDiscoverClaimsCommand renderedChartPath ->
          mapM_ (putStrLn . renderPersistentClaimLine) =<< discoverChartClaimsFile renderedChartPath
        InternalDiscoverHarborOverlayCommand overlayPath ->
          mapM_ putStrLn =<< discoverHarborOverlayImageRefsFile overlayPath
        InternalPublishChartImagesCommand renderedChartPath outputPath ->
          PublishImages.publishChartImagesFile PublishImages.defaultHarborPublishOptions renderedChartPath outputPath
        InternalDemoConfigLoadCommand demoConfigPath -> do
          demoConfig <- decodeDemoConfigFile demoConfigPath
          putStr (renderModelListing demoConfig)
        InternalDemoConfigValidateCommand demoConfigPath ->
          validateDemoConfigFile demoConfigPath
        InternalGeneratePursContractsCommand outputDir -> do
          runtimeMode <- resolveRuntimeMode maybeRuntimeMode
          writeGeneratedPursContracts runtimeMode outputDir
        InternalPulsarRoundTripCommand demoConfigPath modelIdValue inputTextValue -> do
          runtimeMode <- resolveRuntimeMode maybeRuntimeMode
          runInternalPulsarRoundTrip runtimeMode demoConfigPath modelIdValue inputTextValue

runLint :: Maybe RuntimeMode -> IO ()
runLint maybeRuntimeMode = do
  runCabalCommand maybeRuntimeMode ["test", "infernix-haskell-style"]
  runFilesLint
  runChartLint
  runProtoLint
  runDocsLint
  runPythonQualityIfPresent maybeRuntimeMode
  runCabalCommand maybeRuntimeMode ["build", "all"]

runEndToEnd :: Maybe RuntimeMode -> IO ()
runEndToEnd maybeRuntimeMode = do
  commandsAvailable <- platformCommandsAvailableForE2E
  if not commandsAvailable
    then do
      ensureWebDependencies
      ensurePlaywrightBrowsers
      runWebNpmCommand maybeRuntimeMode ["--prefix", "web", "run", "test:e2e"]
    else do
      paths <- discoverPaths
      runtimeModes <-
        case maybeRuntimeMode of
          Just runtimeMode -> pure [runtimeMode]
          Nothing -> do
            cudaSupported <- linuxCudaSupportedOnHost
            pure (filter (\runtimeMode -> runtimeMode /= LinuxCuda || cudaSupported) allRuntimeModes)
      when (AppleSilicon `elem` runtimeModes) $ do
        ensureWebDependencies
        ensurePlaywrightBrowsers
      mapM_ (runRuntimeModeE2E paths) runtimeModes

runRuntimeModeE2E :: Paths -> RuntimeMode -> IO ()
runRuntimeModeE2E paths runtimeMode =
  ( do
      clusterUp (Just runtimeMode)
      maybePort <- readEdgePortMaybe paths
      edgePort <-
        case maybePort of
          Just port -> pure port
          Nothing -> ioError (userError "edge port was not published after cluster up")
      if runtimeMode == AppleSilicon
        then
          withHostBridgeDemo runtimeMode edgePort $
            runHostPlaywright runtimeMode "127.0.0.1" edgePort "control-plane-host" "host-demo-bridge"
        else
          if controlPlaneContext paths == "host-native"
            then
              runPlaywrightImage
                runtimeMode
                Nothing
                "127.0.0.1"
                edgePort
                "cluster-pod"
                "cluster-demo"
            else
              runPlaywrightImage
                runtimeMode
                (Just "kind")
                (kindControlPlaneNodeName paths runtimeMode)
                30090
                "cluster-pod"
                "cluster-demo"
  )
    `finally` clusterDown (Just runtimeMode)

runHostPlaywright :: RuntimeMode -> String -> Int -> String -> String -> IO ()
runHostPlaywright runtimeMode routeProbeHost edgePort expectedDaemonLocation expectedApiUpstreamMode = do
  waitForPlaywrightSurface routeProbeHost edgePort expectedDaemonLocation expectedApiUpstreamMode
  paths <- discoverPaths
  (command, args) <-
    resolveWebNpmInvocation
      [ "--prefix",
        "web",
        "exec",
        "--",
        "playwright",
        "test",
        "./playwright/inference.spec.js",
        "--reporter=list",
        "--timeout=30000"
      ]
  runCommandWithCwdAndEnvRemoving
    (Just runtimeMode)
    ["FORCE_COLOR", "NO_COLOR"]
    [ ("INFERNIX_RUNTIME_MODE", Text.unpack (runtimeModeId runtimeMode)),
      ("INFERNIX_EDGE_PORT", show edgePort),
      ("INFERNIX_PLAYWRIGHT_HOST", routeProbeHost),
      ("INFERNIX_EXPECT_DAEMON_LOCATION", expectedDaemonLocation),
      ("INFERNIX_EXPECT_API_UPSTREAM_MODE", expectedApiUpstreamMode)
    ]
    command
    args
    (repoRoot paths)

withHostBridgeDemo :: RuntimeMode -> Int -> IO () -> IO ()
withHostBridgeDemo runtimeMode edgePort action = do
  paths <- discoverPaths
  activateHostBridgeRoute paths runtimeMode 18081
  executablePath <- resolveDemoExecutable
  environment <- getEnvironment
  let processArgs =
        [ "--runtime-mode",
          Text.unpack (runtimeModeId runtimeMode),
          "serve",
          "--dhall",
          generatedDemoConfigPath paths runtimeMode,
          "--port",
          "18081"
        ]
  (_, _, _, demoHandle) <-
    createProcess
      (proc executablePath processArgs)
        { cwd = Just (repoRoot paths),
          env =
            Just
              ( mergeEnvironment
                  [ ("INFERNIX_CONTROL_PLANE_CONTEXT", "host-native"),
                    ("INFERNIX_DAEMON_LOCATION", "control-plane-host"),
                    ("INFERNIX_CATALOG_SOURCE", "generated-build-root"),
                    ("INFERNIX_DEMO_CONFIG_PATH", generatedDemoConfigPath paths runtimeMode),
                    ("INFERNIX_PUBLICATION_STATE_PATH", publicationStatePath paths),
                    ("INFERNIX_BIND_HOST", "0.0.0.0"),
                    ("INFERNIX_ROUTE_PROBE_BASE_URL", "http://127.0.0.1:" <> show edgePort)
                  ]
                  environment
              )
        }
  waitForPublication edgePort "control-plane-host" "host-demo-bridge"
  action
    `finally` do
      terminateProcess demoHandle
      _ <- waitForProcess demoHandle
      restoreClusterServiceRoute paths
      waitForPublication edgePort "cluster-pod" "cluster-demo"

runInternalPulsarRoundTrip :: RuntimeMode -> FilePath -> String -> String -> IO ()
runInternalPulsarRoundTrip runtimeMode demoConfigPath modelIdValue inputTextValue = do
  paths <- discoverPaths
  demoConfig <- decodeDemoConfigFile demoConfigPath
  requestTopicValue <-
    case requestTopics demoConfig of
      topicValue : _ -> pure topicValue
      [] -> ioError (userError "demo config does not declare any request topics")
  let requestValue =
        InferenceRequest
          { requestModelId = Text.pack modelIdValue,
            inputText = Text.pack inputTextValue
          }
      requestIdValue = Text.pack modelIdValue <> "-request"
  _ <- publishInferenceRequest paths runtimeMode requestTopicValue requestValue
  maybeResult <- waitForInternalPulsarResult paths (resultTopic demoConfig) requestIdValue
  case maybeResult of
    Nothing ->
      ioError
        ( userError
            ( "timed out waiting for Pulsar result for request "
                <> Text.unpack requestIdValue
            )
        )
    Just resultValue -> printInternalPulsarResult resultValue

waitForInternalPulsarResult :: Paths -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
waitForInternalPulsarResult paths resultTopicValue requestIdValue = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure Nothing
      | otherwise = do
          maybeResult <- readPublishedInferenceResultMaybe paths resultTopicValue requestIdValue
          case maybeResult of
            Just resultValue -> pure (Just resultValue)
            Nothing -> do
              threadDelay 250000
              go (remainingAttempts - 1)

printInternalPulsarResult :: InferenceResult -> IO ()
printInternalPulsarResult resultValue = do
  putStrLn ("requestId: " <> Text.unpack (requestId resultValue))
  putStrLn ("status: " <> Text.unpack (status resultValue))
  putStrLn ("resultModelId: " <> Text.unpack (resultModelId resultValue))
  putStrLn ("resultRuntimeMode: " <> Text.unpack (runtimeModeId (resultRuntimeMode resultValue)))
  putStrLn ("resultSelectedEngine: " <> Text.unpack (resultSelectedEngine resultValue))
  case payload resultValue of
    ResultPayload {inlineOutput = Just inlineOutputValue} ->
      putStrLn ("inlineOutput: " <> Text.unpack inlineOutputValue)
    ResultPayload {objectRef = Just objectRefValue} ->
      putStrLn ("objectRef: " <> Text.unpack objectRefValue)
    _ -> pure ()

runPlaywrightImage :: RuntimeMode -> Maybe String -> String -> Int -> String -> String -> IO ()
runPlaywrightImage runtimeMode maybeNetwork routeProbeHost edgePort expectedDaemonLocation expectedApiUpstreamMode = do
  paths <- discoverPaths
  imageRef <- resolvePlaywrightImage paths runtimeMode
  waitForPlaywrightSurface routeProbeHost edgePort expectedDaemonLocation expectedApiUpstreamMode
  runCommand
    (Just runtimeMode)
    "docker"
    ( [ "run",
        "--rm"
      ]
        <> maybe [] (\networkName -> ["--network", networkName]) maybeNetwork
        <> [ "-e",
             "INFERNIX_RUNTIME_MODE=" <> Text.unpack (runtimeModeId runtimeMode),
             "-e",
             "INFERNIX_EDGE_PORT=" <> show edgePort,
             "-e",
             "INFERNIX_PLAYWRIGHT_HOST=" <> routeProbeHost,
             "-e",
             "INFERNIX_EXPECT_DAEMON_LOCATION=" <> expectedDaemonLocation,
             "-e",
             "INFERNIX_EXPECT_API_UPSTREAM_MODE=" <> expectedApiUpstreamMode,
             imageRef,
             "npm",
             "--prefix",
             "web",
             "exec",
             "--",
             "playwright",
             "test",
             "./playwright/inference.spec.js",
             "--reporter=list",
             "--timeout=30000"
           ]
    )

resolvePlaywrightImage :: Paths -> RuntimeMode -> IO String
resolvePlaywrightImage _paths runtimeMode =
  pure
    ( case runtimeMode of
        LinuxCuda -> "infernix-linux-cuda:local"
        _ -> "infernix-linux-cpu:local"
    )

waitForPublication :: Int -> String -> String -> IO ()
waitForPublication edgePort expectedDaemonLocation expectedApiUpstreamMode = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          ioError
            ( userError
                ( "timed out waiting for /api/publication to report daemonLocation="
                    <> expectedDaemonLocation
                    <> " and apiUpstream.mode="
                    <> expectedApiUpstreamMode
                )
            )
      | otherwise = do
          publicationPayload <- loadJsonUrl ("http://127.0.0.1:" <> show edgePort <> "/api/publication")
          if publicationReady publicationPayload
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)
    publicationReady (Just payloadValue) =
      jsonTextAt ["daemonLocation"] payloadValue == Just (Text.pack expectedDaemonLocation)
        && jsonTextAt ["apiUpstream", "mode"] payloadValue == Just (Text.pack expectedApiUpstreamMode)
    publicationReady Nothing = False

waitForPlaywrightSurface :: String -> Int -> String -> String -> IO ()
waitForPlaywrightSurface host edgePort expectedDaemonLocation expectedApiUpstreamMode = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          ioError
            ( userError
                ( "timed out waiting for routed surface at "
                    <> host
                    <> ":"
                    <> show edgePort
                    <> " to serve publication, demo-config, and inference traffic"
                )
            )
      | otherwise = do
          ready <- surfaceReady
          if ready
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)
    surfaceReady = do
      let baseUrl = "http://" <> host <> ":" <> show edgePort
      maybePublication <- loadJsonUrl (baseUrl <> "/api/publication")
      maybeDemoConfig <- loadJsonUrl (baseUrl <> "/api/demo-config")
      maybeHome <- loadTextUrl (baseUrl <> "/")
      case (maybePublication, maybeDemoConfig, maybeHome) of
        (Just publicationPayload, Just demoConfigPayload, Just homeBody) ->
          case firstModelId demoConfigPayload of
            Just firstModel -> do
              let payloadBody =
                    "{\"requestModelId\":"
                      <> show (Text.unpack firstModel)
                      <> ",\"inputText\":\"playwright readiness probe\"}"
              maybeInference <- postJsonUrl (baseUrl <> "/api/inference") payloadBody
              pure
                ( jsonTextAt ["daemonLocation"] publicationPayload == Just (Text.pack expectedDaemonLocation)
                    && jsonTextAt ["apiUpstream", "mode"] publicationPayload == Just (Text.pack expectedApiUpstreamMode)
                    && "Infernix" `isInfixOf` homeBody
                    && maybe False (\inferencePayload -> jsonTextAt ["resultModelId"] inferencePayload == Just firstModel) maybeInference
                )
            Nothing -> pure False
        _ -> pure False
    firstModelId demoConfigPayload =
      case jsonArrayAt ["models"] demoConfigPayload of
        Just (Object firstModel : _) -> KeyMap.lookup (Key.fromText "modelId") firstModel >>= valueText
        _ -> Nothing

runCacheStatus :: Maybe RuntimeMode -> IO ()
runCacheStatus maybeRuntimeMode = do
  paths <- discoverPaths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  manifests <- listCacheManifests paths runtimeMode
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("cacheRoot: " <> modelCacheRoot paths </> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("durableManifestRoot: " <> objectStoreRoot paths </> "manifests" </> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("durableManifestCount: " <> show (length manifests))
  mapM_ printCacheManifest manifests

runCacheEvict :: Maybe RuntimeMode -> Maybe Text.Text -> IO ()
runCacheEvict maybeRuntimeMode maybeModelId = do
  paths <- discoverPaths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  evictedCount <- evictCache paths runtimeMode maybeModelId
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("evictedCacheEntries: " <> show evictedCount)

runCacheRebuild :: Maybe RuntimeMode -> Maybe Text.Text -> IO ()
runCacheRebuild maybeRuntimeMode maybeModelId = do
  paths <- discoverPaths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  rebuiltEntries <- rebuildCache paths runtimeMode maybeModelId
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("rebuiltCacheEntries: " <> show (length rebuiltEntries))
  mapM_ printCacheManifest rebuiltEntries

printCacheManifest :: CacheManifest -> IO ()
printCacheManifest manifest =
  putStrLn
    ( "cacheEntry: "
        <> Text.unpack (cacheModelId manifest)
        <> " -> "
        <> Text.unpack (cacheSelectedEngine manifest)
        <> " ("
        <> Text.unpack (cacheDurableSourceUri manifest)
        <> ")"
    )

renderPersistentClaimLine :: PersistentClaim -> String
renderPersistentClaimLine persistentClaim =
  intercalate
    "\t"
    [ Text.unpack (namespace persistentClaim),
      Text.unpack (release persistentClaim),
      Text.unpack (workload persistentClaim),
      show (ordinal persistentClaim),
      Text.unpack (claim persistentClaim),
      Text.unpack (pvcName persistentClaim),
      Text.unpack (requestedStorage persistentClaim)
    ]

runCabalCommand :: Maybe RuntimeMode -> [String] -> IO ()
runCabalCommand maybeRuntimeMode args = do
  buildDir <- resolveCabalBuildDir
  runCommand maybeRuntimeMode "cabal" (("--builddir=" <> buildDir) : args)

runWebNpmCommand :: Maybe RuntimeMode -> [String] -> IO ()
runWebNpmCommand maybeRuntimeMode npmArgs = do
  (command, args) <- resolveWebNpmInvocation npmArgs
  runCommand maybeRuntimeMode command args

writeGeneratedPursContracts :: RuntimeMode -> FilePath -> IO ()
writeGeneratedPursContracts runtimeMode outputDir = do
  let generatedDir = outputDir </> "Generated"
      tempGeneratedRoot = outputDir </> ".bridge-generated"
      generatedSourceFile = tempGeneratedRoot </> "Infernix" </> "Web" </> "Contracts.purs"
      outputFile = generatedDir </> "Contracts.purs"
      bridgeSwitch = noLenses <> noArgonautCodecs
  createDirectoryIfMissing True generatedDir
  removePathForcibly tempGeneratedRoot `catchAnyIOException` (\_ -> pure ())
  createDirectoryIfMissing True tempGeneratedRoot
  writePSTypesWith bridgeSwitch tempGeneratedRoot (buildBridge (contractArrayBridge <|> defaultBridge)) Contracts.contractSumTypes
  normalizeGeneratedPursContracts runtimeMode generatedSourceFile outputFile
  removePathForcibly tempGeneratedRoot

contractArrayBridge :: BridgePart
contractArrayBridge = (typeName ^== "List" <|> typeName ^== "[]") >> psArray

normalizeGeneratedPursContracts :: RuntimeMode -> FilePath -> FilePath -> IO ()
normalizeGeneratedPursContracts runtimeMode sourceFile outputFile = do
  generatedModule <- readFile sourceFile
  let normalizedModule = unlines (map normalizeLine (filter keepLine (lines generatedModule)))
      finalModule = normalizedModule <> Contracts.renderPursContractFooter runtimeMode
  _ <- evaluate (length finalModule)
  writeFile outputFile finalModule
  where
    normalizeLine line
      | line == "module Infernix.Web.Contracts where" = "module Generated.Contracts where"
      | line == "import Data.Maybe (Maybe, Maybe(..))" = "import Data.Maybe (Maybe)"
      | line == "import Prim (Array, Boolean, String)" = "import Prim (Array, Boolean, Int, String)"
      | line == "import Data.Newtype (class Newtype)" =
          unlines
            [ "import Data.Newtype (class Newtype)",
              "import Simple.JSON as JSON"
            ]
      | otherwise = line

    keepLine line =
      not
        ( "import Data.Generic.Rep " `isPrefixOf` line
            || "import Data.Generic " `isPrefixOf` line
            || "derive instance generic" `isPrefixOf` line
        )

catchAnyIOException :: IO () -> (IOException -> IO ()) -> IO ()
catchAnyIOException = catch

extractRuntimeMode :: [String] -> Either String (Maybe RuntimeMode, [String])
extractRuntimeMode = go Nothing []
  where
    go maybeRuntimeMode acc [] = Right (maybeRuntimeMode, reverse acc)
    go _ _ ["--runtime-mode"] = Left "Missing value for --runtime-mode"
    go _ acc ("--runtime-mode" : rawValue : rest) =
      case parseRuntimeMode (Text.pack rawValue) of
        Nothing -> Left ("Unsupported runtime mode: " <> rawValue)
        Just runtimeMode ->
          go (Just runtimeMode) acc rest
    go maybeRuntimeMode acc (value : rest) =
      go maybeRuntimeMode (value : acc) rest

runCommand :: Maybe RuntimeMode -> FilePath -> [String] -> IO ()
runCommand maybeRuntimeMode command args = do
  paths <- discoverPaths
  runCommandWithCwd maybeRuntimeMode command args (repoRoot paths)

runCommandWithCwd :: Maybe RuntimeMode -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwd maybeRuntimeMode =
  runCommandWithCwdAndEnv maybeRuntimeMode []

resolveDemoExecutable :: IO FilePath
resolveDemoExecutable = do
  buildDir <- resolveCabalBuildDir
  trimTrailingWhitespace <$> readProcess "cabal" ["--builddir=" <> buildDir, "list-bin", "exe:infernix-demo"] ""

runCommandWithCwdAndEnv :: Maybe RuntimeMode -> [(String, String)] -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwdAndEnv maybeRuntimeMode =
  runCommandWithCwdAndEnvRemoving maybeRuntimeMode []

runCommandWithCwdAndEnvRemoving :: Maybe RuntimeMode -> [String] -> [(String, String)] -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwdAndEnvRemoving maybeRuntimeMode removedEnvironmentNames extraEnvironment command args workingDirectory = do
  environment <- getEnvironment
  let augmentedEnvironment =
        mergeEnvironment runtimeModeBindings (mergeEnvironment extraEnvironment (removeEnvironmentVariables removedEnvironmentNames environment))
      runtimeModeBindings =
        case maybeRuntimeMode of
          Nothing -> []
          Just runtimeMode ->
            [("INFERNIX_RUNTIME_MODE", Text.unpack (runtimeModeId runtimeMode))]
  (_, _, _, processHandle) <-
    createProcess
      (proc command args)
        { env = Just augmentedEnvironment,
          cwd = Just workingDirectory
        }
  exitCode <- waitForProcess processHandle
  case exitCode of
    ExitSuccess -> pure ()
    _ -> exitWith exitCode

mergeEnvironment :: [(String, String)] -> [(String, String)] -> [(String, String)]
mergeEnvironment overrides environment =
  overrides <> filter (\(name, _) -> name `notElem` overrideNames) environment
  where
    overrideNames = map fst overrides

removeEnvironmentVariables :: [String] -> [(String, String)] -> [(String, String)]
removeEnvironmentVariables names =
  filter (\(name, _) -> name `notElem` names)

trimTrailingWhitespace :: String -> String
trimTrailingWhitespace =
  reverse . dropWhile (`elem` [' ', '\n', '\r', '\t']) . reverse

loadJsonUrl :: String -> IO (Maybe Value)
loadJsonUrl url = do
  response <- try (readProcess "curl" ["-fsS", url] "") :: IO (Either IOException String)
  case response of
    Left _ -> pure Nothing
    Right payload ->
      case eitherDecode (LazyChar8.pack payload) of
        Left _ -> pure Nothing
        Right decodedValue -> pure (Just decodedValue)

loadTextUrl :: String -> IO (Maybe String)
loadTextUrl url = do
  response <- try (readProcess "curl" ["-fsS", url] "") :: IO (Either IOException String)
  case response of
    Left _ -> pure Nothing
    Right payload -> pure (Just payload)

postJsonUrl :: String -> String -> IO (Maybe Value)
postJsonUrl url body = do
  response <-
    try
      ( readProcess
          "curl"
          ["-fsS", "-X", "POST", "-H", "Content-Type: application/json", "-d", body, url]
          ""
      ) ::
      IO (Either IOException String)
  case response of
    Left _ -> pure Nothing
    Right payload ->
      case eitherDecode (LazyChar8.pack payload) of
        Left _ -> pure Nothing
        Right decodedValue -> pure (Just decodedValue)

jsonTextAt :: [Text.Text] -> Value -> Maybe Text.Text
jsonTextAt [] value = valueText value
jsonTextAt (segment : remainingSegments) (Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= jsonTextAt remainingSegments
jsonTextAt _ _ = Nothing

jsonArrayAt :: [Text.Text] -> Value -> Maybe [Value]
jsonArrayAt [] (Array values) = Just (Vector.toList values)
jsonArrayAt (segment : remainingSegments) (Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= jsonArrayAt remainingSegments
jsonArrayAt _ _ = Nothing

valueText :: Value -> Maybe Text.Text
valueText (String textValue) = Just textValue
valueText _ = Nothing

runPythonQualityIfPresent :: Maybe RuntimeMode -> IO ()
runPythonQualityIfPresent maybeRuntimeMode = do
  paths <- discoverPaths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  let projectDirectory = pythonProjectDirectory paths runtimeMode
  adaptersPresent <- pythonAdaptersPresent projectDirectory
  when adaptersPresent $ do
    ensurePythonQualityDependencies paths projectDirectory
    poetryExecutable <- ensurePoetryExecutable paths
    runCommandWithCwdAndEnv
      maybeRuntimeMode
      [("POETRY_VIRTUALENVS_IN_PROJECT", "true")]
      poetryExecutable
      ["--directory", projectDirectory, "run", "check-code"]
      projectDirectory

ensurePythonAdapterDependencies :: Maybe RuntimeMode -> IO ()
ensurePythonAdapterDependencies maybeRuntimeMode = do
  paths <- discoverPaths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  let projectDirectory = pythonProjectDirectory paths runtimeMode
  adaptersPresent <- pythonAdaptersPresent projectDirectory
  when adaptersPresent $ do
    ensurePythonQualityDependencies paths projectDirectory

ensurePythonQualityDependencies :: Paths -> FilePath -> IO ()
ensurePythonQualityDependencies = ensurePoetryProjectReady

syncBuildRootExecutable :: IO ()
syncBuildRootExecutable = do
  paths <- discoverPaths
  ensureRepoLayout paths
  currentExecutable <- getExecutablePath
  let targetExecutable = buildRoot paths </> takeFileName currentExecutable
  if currentExecutable == targetExecutable
    then pure ()
    else do
      createDirectoryIfMissing True (buildRoot paths)
      copyFile currentExecutable targetExecutable
      currentPermissions <- getPermissions currentExecutable
      setPermissions targetExecutable currentPermissions
