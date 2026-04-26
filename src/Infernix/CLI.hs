{-# LANGUAGE OverloadedStrings #-}

module Infernix.CLI
  ( main,
    extractRuntimeMode,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, evaluate, finally, try)
import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecode)
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.Maybe (fromMaybe, isJust)
import Data.Text qualified as Text
import Data.Vector qualified as Vector
import Generated.Contracts qualified as Contracts
import Infernix.Cluster
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.Config
import Infernix.DemoConfig (decodeDemoConfigFile, renderModelListing, validateDemoConfigFile)
import Infernix.Edge (runEdgeProxy)
import Infernix.Gateway (runGatewayProxy)
import Infernix.Lint.Chart (runChartLint)
import Infernix.Lint.Docs (runDocsLint)
import Infernix.Lint.Files (runFilesLint)
import Infernix.Lint.Proto (runProtoLint)
import Infernix.Runtime (evictCache, listCacheManifests, rebuildCache)
import Infernix.Service
import Infernix.Storage (readEdgePortMaybe)
import Infernix.Types
  ( CacheManifest (..),
    PersistentClaim (..),
    RuntimeMode (LinuxCuda),
    allRuntimeModes,
    parseRuntimeMode,
    runtimeModeId,
  )
import Language.PureScript.Bridge (buildBridge, defaultBridge, writePSTypesWith)
import Language.PureScript.Bridge.Builder (BridgePart, (^==))
import Language.PureScript.Bridge.CodeGenSwitches (noArgonautCodecs, noLenses)
import Language.PureScript.Bridge.PSTypes (psArray)
import Language.PureScript.Bridge.TypeInfo (typeName)
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getPermissions,
    listDirectory,
    setPermissions,
  )
import System.Environment (getArgs, getEnvironment, getExecutablePath)
import System.Exit (ExitCode (ExitSuccess), exitFailure, exitWith)
import System.FilePath (takeFileName, (</>))
import System.Process (CreateProcess (cwd, env), createProcess, proc, readProcess, terminateProcess, waitForProcess)

main :: IO ()
main = do
  syncBuildRootExecutable
  args <- getArgs
  case extractRuntimeMode args of
    Left message -> do
      putStrLn message
      exitFailure
    Right (maybeRuntimeMode, remainingArgs) -> dispatch maybeRuntimeMode remainingArgs

dispatch :: Maybe RuntimeMode -> [String] -> IO ()
dispatch maybeRuntimeMode args = case args of
  [] -> putStrLn helpText
  ["--help"] -> putStrLn helpText
  ["cluster", "--help"] -> putStrLn clusterHelpText
  ["test", "--help"] -> putStrLn testHelpText
  ["lint", "--help"] -> putStrLn lintHelpText
  ["internal", "--help"] -> putStrLn internalHelpText
  _ -> do
    ensureAppleHostPrerequisites
    case args of
      ["service"] -> runService maybeRuntimeMode
      ["edge"] -> runEdgeProxy
      ["gateway", "harbor"] -> runGatewayProxy "harbor"
      ["gateway", "minio"] -> runGatewayProxy "minio"
      ["gateway", "pulsar"] -> runGatewayProxy "pulsar"
      ["cluster", "up"] -> clusterUp maybeRuntimeMode
      ["cluster", "down"] -> clusterDown maybeRuntimeMode
      ["cluster", "status"] -> clusterStatus maybeRuntimeMode
      ["cache", "status"] -> runCacheStatus maybeRuntimeMode
      ["cache", "evict"] -> runCacheEvict maybeRuntimeMode Nothing
      ["cache", "evict", "--model", modelIdValue] -> runCacheEvict maybeRuntimeMode (Just (Text.pack modelIdValue))
      ["cache", "rebuild"] -> runCacheRebuild maybeRuntimeMode Nothing
      ["cache", "rebuild", "--model", modelIdValue] -> runCacheRebuild maybeRuntimeMode (Just (Text.pack modelIdValue))
      "kubectl" : kubectlArgs -> runKubectlCompat kubectlArgs
      ["docs", "check"] -> runDocsLint
      ["lint", "files"] -> runFilesLint
      ["lint", "docs"] -> runDocsLint
      ["lint", "proto"] -> runProtoLint
      ["lint", "chart"] -> do
        runChartLint
      ["test", "lint"] -> runLint maybeRuntimeMode
      ["test", "unit"] -> do
        ensureWebDependencies
        ensurePythonAdapterDependencies maybeRuntimeMode
        runCabalCommand maybeRuntimeMode ["test", "infernix-unit"]
        runCommand maybeRuntimeMode "npm" ["--prefix", "web", "run", "test:unit"]
      ["test", "integration"] -> runCabalCommand maybeRuntimeMode ["test", "infernix-integration"]
      ["test", "e2e"] -> runEndToEnd maybeRuntimeMode
      ["test", "all"] -> do
        ensureWebDependencies
        runLint maybeRuntimeMode
        ensurePythonAdapterDependencies maybeRuntimeMode
        runCabalCommand maybeRuntimeMode ["test", "infernix-unit"]
        runCommand maybeRuntimeMode "npm" ["--prefix", "web", "run", "test:unit"]
        runCabalCommand maybeRuntimeMode ["test", "infernix-integration"]
        runEndToEnd maybeRuntimeMode
      ["internal", "discover", "images", renderedChartPath] ->
        mapM_ putStrLn =<< discoverChartImagesFile renderedChartPath
      ["internal", "discover", "claims", renderedChartPath] ->
        mapM_ (putStrLn . renderPersistentClaimLine) =<< discoverChartClaimsFile renderedChartPath
      ["internal", "discover", "harbor-overlay", overlayPath] ->
        mapM_ putStrLn =<< discoverHarborOverlayImageRefsFile overlayPath
      ["internal", "publish-chart-images", renderedChartPath, outputPath] ->
        PublishImages.publishChartImagesFile PublishImages.defaultHarborPublishOptions renderedChartPath outputPath
      ["internal", "demo-config", "load", demoConfigPath] -> do
        demoConfig <- decodeDemoConfigFile demoConfigPath
        putStr (renderModelListing demoConfig)
      ["internal", "demo-config", "validate", demoConfigPath] ->
        validateDemoConfigFile demoConfigPath
      ["internal", "generate-purs-contracts", outputDir] -> do
        runtimeMode <- resolveRuntimeMode maybeRuntimeMode
        writeGeneratedPursContracts runtimeMode outputDir
      _ -> do
        putStrLn helpText
        exitFailure

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
  ensureWebDependencies
  ensurePlaywrightBrowsers
  commandsAvailable <- platformCommandsAvailableForE2E
  if not commandsAvailable
    then runCommand maybeRuntimeMode "npm" ["--prefix", "web", "run", "test:e2e"]
    else do
      paths <- discoverPaths
      runtimeModes <-
        case maybeRuntimeMode of
          Just runtimeMode -> pure [runtimeMode]
          Nothing -> do
            cudaSupported <- linuxCudaSupportedOnHost
            pure (filter (\runtimeMode -> runtimeMode /= LinuxCuda || cudaSupported) allRuntimeModes)
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
      if controlPlaneContext paths == "host-native"
        then
          withHostBridgeDemo runtimeMode edgePort $
            runPlaywrightImage runtimeMode Nothing "127.0.0.1" edgePort "control-plane-host" "host-demo-bridge"
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
             "run",
             "test:e2e:image"
           ]
    )

resolvePlaywrightImage :: Paths -> RuntimeMode -> IO String
resolvePlaywrightImage paths runtimeMode = do
  let overridePath =
        buildRoot paths
          </> ("harbor-image-overrides-" <> Text.unpack (runtimeModeId runtimeMode) <> ".yaml")
  overrideExists <- doesFileExist overridePath
  if not overrideExists
    then pure "infernix-web:local"
    else do
      overrideLines <- lines <$> readFile overridePath
      pure (fromMaybe "infernix-web:local" (publishedWebImageRef overrideLines))

publishedWebImageRef :: [String] -> Maybe String
publishedWebImageRef overrideLines = do
  webSection <- nestedYamlSection 0 "web:" overrideLines
  imageSection <- nestedYamlSection 2 "image:" webSection
  repository <- lookupYamlScalar 4 "repository:" imageSection
  tag <- lookupYamlScalar 4 "tag:" imageSection
  pure (repository <> ":" <> tag)

nestedYamlSection :: Int -> String -> [String] -> Maybe [String]
nestedYamlSection indent header = go
  where
    prefix = replicate indent ' ' <> header
    go [] = Nothing
    go (line : rest)
      | line == prefix =
          Just
            ( takeWhile
                (\candidate -> null (trimLeft candidate) || leadingSpaces candidate > indent)
                rest
            )
      | otherwise = go rest

lookupYamlScalar :: Int -> String -> [String] -> Maybe String
lookupYamlScalar indent fieldLabel = go
  where
    prefix = replicate indent ' ' <> fieldLabel
    go [] = Nothing
    go (line : rest)
      | prefix `isPrefixOf` line = Just (trimLeft (drop (length prefix) line))
      | otherwise = go rest

leadingSpaces :: String -> Int
leadingSpaces = length . takeWhile (== ' ')

trimLeft :: String -> String
trimLeft = dropWhile (== ' ')

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

writeGeneratedPursContracts :: RuntimeMode -> FilePath -> IO ()
writeGeneratedPursContracts runtimeMode outputDir = do
  let generatedDir = outputDir </> "Generated"
      outputFile = generatedDir </> "Contracts.purs"
      bridgeSwitch = noLenses <> noArgonautCodecs
  createDirectoryIfMissing True generatedDir
  writePSTypesWith bridgeSwitch outputDir (buildBridge (contractArrayBridge <|> defaultBridge)) Contracts.contractSumTypes
  appendFile outputFile (Contracts.renderPursContractFooter runtimeMode)
  normalizeGeneratedPursContracts outputFile

contractArrayBridge :: BridgePart
contractArrayBridge = (typeName ^== "List" <|> typeName ^== "[]") >> psArray

normalizeGeneratedPursContracts :: FilePath -> IO ()
normalizeGeneratedPursContracts outputFile = do
  generatedModule <- readFile outputFile
  let normalizedModule = unlines (map normalizeLine (filter keepLine (lines generatedModule)))
  _ <- evaluate (length normalizedModule)
  writeFile outputFile normalizedModule
  where
    normalizeLine line
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

runCommandInDirectory :: Maybe RuntimeMode -> FilePath -> [String] -> FilePath -> IO ()
runCommandInDirectory = runCommandWithCwd

runCommandWithCwd :: Maybe RuntimeMode -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwd maybeRuntimeMode =
  runCommandWithCwdAndEnv maybeRuntimeMode []

resolveDemoExecutable :: IO FilePath
resolveDemoExecutable = do
  buildDir <- resolveCabalBuildDir
  trimTrailingWhitespace <$> readProcess "cabal" ["--builddir=" <> buildDir, "list-bin", "exe:infernix-demo"] ""

runCommandWithCwdAndEnv :: Maybe RuntimeMode -> [(String, String)] -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwdAndEnv maybeRuntimeMode extraEnvironment command args workingDirectory = do
  environment <- getEnvironment
  let augmentedEnvironment =
        mergeEnvironment runtimeModeBindings (mergeEnvironment extraEnvironment environment)
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

ensureWebDependencies :: IO ()
ensureWebDependencies = do
  paths <- discoverPaths
  let webRoot = repoRoot paths </> "web"
  depsDirectoryPresent <- doesDirectoryExist (webRoot </> "node_modules")
  toolchainPresent <- webToolchainPresent webRoot
  if depsDirectoryPresent && toolchainPresent
    then pure ()
    else runCommandInDirectory Nothing "npm" ["--prefix", "web", "ci"] (repoRoot paths)

webToolchainPresent :: FilePath -> IO Bool
webToolchainPresent webRoot =
  and
    <$> mapM
      doesFileExist
      [ webRoot </> "node_modules" </> "playwright" </> "package.json",
        webRoot </> "node_modules" </> "purescript" </> "package.json",
        webRoot </> "node_modules" </> "spago" </> "package.json",
        webRoot </> "node_modules" </> "esbuild" </> "package.json"
      ]

ensurePlaywrightBrowsers :: IO ()
ensurePlaywrightBrowsers = do
  paths <- discoverPaths
  runCommandInDirectory Nothing "npx" ["playwright", "install", "chromium"] (repoRoot paths </> "web")

runPythonQualityIfPresent :: Maybe RuntimeMode -> IO ()
runPythonQualityIfPresent maybeRuntimeMode = do
  adaptersPresent <- pythonAdaptersPresent
  when adaptersPresent $ do
    paths <- discoverPaths
    ensurePythonQualityDependencies maybeRuntimeMode paths
    runCommandWithCwdAndEnv
      maybeRuntimeMode
      [("POETRY_VIRTUALENVS_IN_PROJECT", "true")]
      "bash"
      ["tools/python_quality.sh"]
      (repoRoot paths)

ensurePythonAdapterDependencies :: Maybe RuntimeMode -> IO ()
ensurePythonAdapterDependencies maybeRuntimeMode = do
  paths <- discoverPaths
  adaptersPresent <- pythonAdaptersPresent
  when adaptersPresent $ do
    ensurePythonQualityDependencies maybeRuntimeMode paths

pythonAdaptersPresent :: IO Bool
pythonAdaptersPresent = do
  paths <- discoverPaths
  let adaptersRoot = repoRoot paths </> "python" </> "adapters"
  adaptersDirectoryPresent <- doesDirectoryExist adaptersRoot
  if not adaptersDirectoryPresent
    then pure False
    else not . null <$> listDirectory adaptersRoot

ensurePythonQualityDependencies :: Maybe RuntimeMode -> Paths -> IO ()
ensurePythonQualityDependencies maybeRuntimeMode paths = do
  let venvBin = repoRoot paths </> "python" </> ".venv" </> "bin"
      requiredTools = ["mypy", "black", "ruff"]
  toolsReady <- allM (doesFileExist . (venvBin </>)) requiredTools
  unless toolsReady $
    runCommandWithCwdAndEnv
      maybeRuntimeMode
      [("POETRY_VIRTUALENVS_IN_PROJECT", "true")]
      "poetry"
      ["install", "--directory", "python", "--no-root"]
      (repoRoot paths)

allM :: (Monad m) => (a -> m Bool) -> [a] -> m Bool
allM predicate = go
  where
    go [] = pure True
    go (value : rest) = do
      matches <- predicate value
      if matches
        then go rest
        else pure False

platformCommandsAvailableForE2E :: IO Bool
platformCommandsAvailableForE2E = do
  availableCommands <- mapM findExecutable ["docker", "helm", "kind", "kubectl"]
  pure (all isJust availableCommands)

ensureAppleHostPrerequisites :: IO ()
ensureAppleHostPrerequisites = pure ()

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

helpText :: String
helpText =
  unlines
    [ "infernix [--runtime-mode apple-silicon|linux-cpu|linux-cuda]",
      "",
      "Commands:",
      "  infernix service",
      "  infernix edge",
      "  infernix gateway harbor|minio|pulsar",
      "  infernix cluster up",
      "  infernix cluster down",
      "  infernix cluster status",
      "  infernix cache status",
      "  infernix cache evict [--model MODEL_ID]",
      "  infernix cache rebuild [--model MODEL_ID]",
      "  infernix kubectl ...",
      "  infernix lint files|docs|proto|chart",
      "  infernix test lint",
      "  infernix test unit",
      "  infernix test integration",
      "  infernix test e2e",
      "  infernix test all",
      "  infernix docs check",
      "  infernix internal generate-purs-contracts PATH",
      "  infernix internal discover {images,claims,harbor-overlay} PATH",
      "  infernix internal publish-chart-images RENDERED_CHART OUTPUT",
      "  infernix internal demo-config {load,validate} PATH"
    ]

clusterHelpText :: String
clusterHelpText =
  unlines
    [ "infernix cluster up",
      "infernix cluster down",
      "infernix cluster status"
    ]

testHelpText :: String
testHelpText =
  unlines
    [ "infernix test lint",
      "infernix test unit",
      "infernix test integration",
      "infernix test e2e",
      "infernix test all"
    ]

lintHelpText :: String
lintHelpText =
  unlines
    [ "infernix lint files",
      "infernix lint docs",
      "infernix lint proto",
      "infernix lint chart"
    ]

internalHelpText :: String
internalHelpText =
  unlines
    [ "infernix internal generate-purs-contracts PATH",
      "infernix internal discover images RENDERED_CHART",
      "infernix internal discover claims RENDERED_CHART",
      "infernix internal discover harbor-overlay OVERLAY",
      "infernix internal publish-chart-images RENDERED_CHART OUTPUT",
      "infernix internal demo-config load PATH",
      "infernix internal demo-config validate PATH"
    ]
