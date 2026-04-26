{-# LANGUAGE OverloadedStrings #-}

module Infernix.CLI
  ( main,
    extractRuntimeMode,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (finally)
import Data.List (intercalate, isPrefixOf)
import Data.Maybe (fromMaybe)
import Data.Text qualified as Text
import Infernix.Cluster
import Infernix.Config
import Infernix.Models
import Infernix.Runtime (evictCache, listCacheManifests, rebuildCache)
import Infernix.Service
import Infernix.Storage (readEdgePortMaybe)
import Infernix.Types
  ( CacheManifest (..),
    ModelDescriptor (..),
    RequestField (..),
    RuntimeMode (LinuxCuda),
    allRuntimeModes,
    parseRuntimeMode,
    runtimeModeId,
  )
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getPermissions,
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
      ["service"] -> runService maybeRuntimeMode Nothing
      ["service", "--port", port] -> runService maybeRuntimeMode (Just (read port))
      ["edge"] -> runPythonTool maybeRuntimeMode "tools/edge_proxy.py" []
      ["gateway", "harbor"] -> runPortalSurface maybeRuntimeMode "harbor"
      ["gateway", "minio"] -> runPortalSurface maybeRuntimeMode "minio"
      ["gateway", "pulsar"] -> runPortalSurface maybeRuntimeMode "pulsar"
      ["cluster", "up"] -> clusterUp maybeRuntimeMode
      ["cluster", "down"] -> clusterDown maybeRuntimeMode
      ["cluster", "status"] -> clusterStatus maybeRuntimeMode
      ["cache", "status"] -> runCacheStatus maybeRuntimeMode
      ["cache", "evict"] -> runCacheEvict maybeRuntimeMode Nothing
      ["cache", "evict", "--model", modelIdValue] -> runCacheEvict maybeRuntimeMode (Just (Text.pack modelIdValue))
      ["cache", "rebuild"] -> runCacheRebuild maybeRuntimeMode Nothing
      ["cache", "rebuild", "--model", modelIdValue] -> runCacheRebuild maybeRuntimeMode (Just (Text.pack modelIdValue))
      "kubectl" : kubectlArgs -> runKubectlCompat kubectlArgs
      ["docs", "check"] -> runCommand maybeRuntimeMode "python3" ["tools/docs_check.py"]
      ["lint", "files"] -> runCommand maybeRuntimeMode "python3" ["tools/lint_check.py"]
      ["lint", "docs"] -> runCommand maybeRuntimeMode "python3" ["tools/docs_check.py"]
      ["lint", "proto"] -> runCommand maybeRuntimeMode "python3" ["tools/proto_check.py"]
      ["lint", "chart"] -> do
        runCommand maybeRuntimeMode "python3" ["tools/platform_asset_check.py"]
        runCommand maybeRuntimeMode "python3" ["tools/helm_chart_check.py"]
      ["test", "lint"] -> runLint maybeRuntimeMode
      ["test", "unit"] -> do
        ensureWebDependencies
        runCabalCommand maybeRuntimeMode ["test", "infernix-unit"]
        runCommand maybeRuntimeMode "npm" ["--prefix", "web", "run", "test:unit"]
      ["test", "integration"] -> runCabalCommand maybeRuntimeMode ["test", "infernix-integration"]
      ["test", "e2e"] -> runEndToEnd maybeRuntimeMode
      ["test", "all"] -> do
        ensureWebDependencies
        runLint maybeRuntimeMode
        runCabalCommand maybeRuntimeMode ["test", "infernix-unit"]
        runCommand maybeRuntimeMode "npm" ["--prefix", "web", "run", "test:unit"]
        runCabalCommand maybeRuntimeMode ["test", "infernix-integration"]
        runEndToEnd maybeRuntimeMode
      ["internal", "discover", "images", renderedChartPath] ->
        runCommand maybeRuntimeMode "python3" ["tools/discover_chart_images.py", renderedChartPath]
      ["internal", "discover", "claims", renderedChartPath] ->
        runCommand maybeRuntimeMode "python3" ["tools/discover_chart_claims.py", renderedChartPath]
      ["internal", "discover", "harbor-overlay", overlayPath] ->
        runCommand maybeRuntimeMode "python3" ["tools/list_harbor_overlay_images.py", overlayPath]
      ["internal", "publish-chart-images", renderedChartPath, outputPath] ->
        runCommand maybeRuntimeMode "python3" ["tools/publish_chart_images.py", renderedChartPath, outputPath]
      ["internal", "demo-config", "load", demoConfigPath] ->
        runCommand maybeRuntimeMode "python3" ["tools/demo_config.py", demoConfigPath]
      ["internal", "demo-config", "validate", demoConfigPath] ->
        runCommand maybeRuntimeMode "python3" ["tools/demo_config.py", demoConfigPath]
      ["internal", "generate-web-contracts", outputDir] -> do
        runtimeMode <- resolveRuntimeMode maybeRuntimeMode
        writeGeneratedContracts runtimeMode outputDir
      ["internal", "generate-purs-contracts", outputDir] -> do
        runtimeMode <- resolveRuntimeMode maybeRuntimeMode
        writeGeneratedPursContracts runtimeMode outputDir
      _ -> do
        putStrLn helpText
        exitFailure

runPythonTool :: Maybe RuntimeMode -> FilePath -> [String] -> IO ()
runPythonTool maybeRuntimeMode scriptPath args = do
  paths <- discoverPaths
  runCommandWithCwdAndEnv
    maybeRuntimeMode
    []
    "python3"
    ([repoRoot paths </> scriptPath] <> args)
    (repoRoot paths)

runPortalSurface :: Maybe RuntimeMode -> String -> IO ()
runPortalSurface maybeRuntimeMode surface =
  do
    paths <- discoverPaths
    runCommandWithCwdAndEnv
      maybeRuntimeMode
      [("INFERNIX_PORTAL_SURFACE", surface)]
      "python3"
      [repoRoot paths </> "tools" </> "portal_surface.py"]
      (repoRoot paths)

runLint :: Maybe RuntimeMode -> IO ()
runLint maybeRuntimeMode = do
  runCommand maybeRuntimeMode "python3" ["tools/haskell_style_check.py"]
  runCommand maybeRuntimeMode "python3" ["tools/lint_check.py"]
  runCommand maybeRuntimeMode "python3" ["tools/platform_asset_check.py"]
  runCommand maybeRuntimeMode "python3" ["tools/helm_chart_check.py"]
  runCommand maybeRuntimeMode "python3" ["tools/proto_check.py"]
  runCommand maybeRuntimeMode "python3" ["tools/docs_check.py"]
  runCabalCommand maybeRuntimeMode ["build", "all"]

runEndToEnd :: Maybe RuntimeMode -> IO ()
runEndToEnd maybeRuntimeMode = do
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
          withHostBridgeService runtimeMode edgePort $
            runPlaywrightImage runtimeMode Nothing "127.0.0.1" edgePort "control-plane-host" "host-daemon-bridge"
        else
          runPlaywrightImage
            runtimeMode
            (Just "kind")
            (kindControlPlaneNodeName paths runtimeMode)
            30090
            "cluster-pod"
            "cluster-service"
  )
    `finally` clusterDown (Just runtimeMode)

withHostBridgeService :: RuntimeMode -> Int -> IO () -> IO ()
withHostBridgeService runtimeMode edgePort action = do
  paths <- discoverPaths
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
          Text.unpack (runtimeModeId runtimeMode),
          "--control-plane-context",
          "host-native",
          "--daemon-location",
          "control-plane-host",
          "--catalog-source",
          "generated-build-root",
          "--demo-config",
          generatedDemoConfigPath paths runtimeMode,
          "--mounted-demo-config",
          watchedDemoConfigPath runtimeMode,
          "--publication-state",
          publicationStatePath paths,
          "--route-probe-base-url",
          "http://127.0.0.1:" <> show edgePort
        ]
  (_, _, _, serviceHandle) <-
    createProcess
      (proc "python3" processArgs)
        { cwd = Just (repoRoot paths)
        }
  waitForPublication edgePort "control-plane-host" "host-daemon-bridge"
  action
    `finally` do
      terminateProcess serviceHandle
      _ <- waitForProcess serviceHandle
      restoreClusterServiceRoute paths
      waitForPublication edgePort "cluster-pod" "cluster-service"

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
          output <-
            readProcess
              "python3"
              [ "-c",
                unlines
                  [ "import json",
                    "import sys",
                    "import urllib.request",
                    "port = sys.argv[1]",
                    "expected_daemon = sys.argv[2]",
                    "expected_mode = sys.argv[3]",
                    "try:",
                    "    with urllib.request.urlopen(f'http://127.0.0.1:{port}/api/publication', timeout=5) as response:",
                    "        payload = json.load(response)",
                    "except Exception:",
                    "    print('pending')",
                    "else:",
                    "    daemon = payload.get('daemonLocation')",
                    "    upstream_mode = (payload.get('apiUpstream') or {}).get('mode')",
                    "    if daemon == expected_daemon and upstream_mode == expected_mode:",
                    "        print('ready')",
                    "    else:",
                    "        print('pending')"
                  ],
                show edgePort,
                expectedDaemonLocation,
                expectedApiUpstreamMode
              ]
              ""
          if "ready" `elem` words output
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)

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
          output <-
            readProcess
              "python3"
              [ "-c",
                unlines
                  [ "import json",
                    "import sys",
                    "import urllib.request",
                    "base_url = f'http://{sys.argv[1]}:{sys.argv[2]}'",
                    "expected_daemon = sys.argv[3]",
                    "expected_mode = sys.argv[4]",
                    "def load_json(path, timeout=5, data=None):",
                    "    request = urllib.request.Request(base_url + path, data=data)",
                    "    request.add_header('Content-Type', 'application/json') if data is not None else None",
                    "    with urllib.request.urlopen(request, timeout=timeout) as response:",
                    "        return json.load(response)",
                    "try:",
                    "    publication = load_json('/api/publication')",
                    "    demo_config = load_json('/api/demo-config')",
                    "    with urllib.request.urlopen(base_url + '/', timeout=5) as response:",
                    "        home = response.read().decode('utf-8', errors='replace')",
                    "    models = demo_config.get('models') or []",
                    "    if not models:",
                    "        raise ValueError('demo config did not publish any models')",
                    "    probe_payload = json.dumps({",
                    "        'requestModelId': models[0]['modelId'],",
                    "        'inputText': 'playwright readiness probe'",
                    "    }).encode('utf-8')",
                    "    inference = load_json('/api/inference', timeout=15, data=probe_payload)",
                    "except Exception:",
                    "    print('pending')",
                    "else:",
                    "    daemon = publication.get('daemonLocation')",
                    "    upstream_mode = (publication.get('apiUpstream') or {}).get('mode')",
                    "    if daemon == expected_daemon and upstream_mode == expected_mode and 'Infernix' in home and inference.get('resultModelId') == models[0].get('modelId'):",
                    "        print('ready')",
                    "    else:",
                    "        print('pending')"
                  ],
                host,
                show edgePort,
                expectedDaemonLocation,
                expectedApiUpstreamMode
              ]
              ""
          if "ready" `elem` words output
            then pure ()
            else do
              threadDelay 1000000
              go (remainingAttempts - 1)

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

runCabalCommand :: Maybe RuntimeMode -> [String] -> IO ()
runCabalCommand maybeRuntimeMode args = do
  buildDir <- resolveCabalBuildDir
  runCommand maybeRuntimeMode "cabal" (("--builddir=" <> buildDir) : args)

writeGeneratedContracts :: RuntimeMode -> FilePath -> IO ()
writeGeneratedContracts runtimeMode outputDir = do
  let generatedDir = outputDir </> "Generated"
      outputFile = generatedDir </> "contracts.js"
  createDirectoryIfMissing True generatedDir
  writeFile outputFile (renderContractsModule runtimeMode (catalogForMode runtimeMode))

writeGeneratedPursContracts :: RuntimeMode -> FilePath -> IO ()
writeGeneratedPursContracts runtimeMode outputDir = do
  let generatedDir = outputDir </> "Generated"
      outputFile = generatedDir </> "Contracts.purs"
  createDirectoryIfMissing True generatedDir
  writeFile outputFile (renderPursContractsModule runtimeMode (catalogForMode runtimeMode))

renderContractsModule :: RuntimeMode -> [ModelDescriptor] -> String
renderContractsModule runtimeMode models =
  unlines
    [ "export const apiBasePath = '/api';",
      "export const runtimeMode = " <> show (Text.unpack (runtimeModeId runtimeMode)) <> ";",
      "export const maxInlineOutputLength = 80;",
      "export const models = [",
      intercalate ",\n" (map renderModel models),
      "];"
    ]
  where
    renderModel model =
      "  { matrixRowId: "
        <> show (Text.unpack (matrixRowId model))
        <> ", modelId: "
        <> show (Text.unpack (modelId model))
        <> ", displayName: "
        <> show (Text.unpack (displayName model))
        <> ", family: "
        <> show (Text.unpack (family model))
        <> ", description: "
        <> show (Text.unpack (description model))
        <> ", artifactType: "
        <> show (Text.unpack (artifactType model))
        <> ", referenceModel: "
        <> show (Text.unpack (referenceModel model))
        <> ", downloadUrl: "
        <> show (Text.unpack (downloadUrl model))
        <> ", selectedEngine: "
        <> show (Text.unpack (selectedEngine model))
        <> ", runtimeLane: "
        <> show (Text.unpack (runtimeLane model))
        <> ", requiresGpu: "
        <> jsBool (requiresGpu model)
        <> ", notes: "
        <> show (Text.unpack (notes model))
        <> ", requestShape: [{ name: 'inputText', label: "
        <> show (Text.unpack (fieldLabel model))
        <> ", fieldType: 'text' }] }"
    fieldLabel model =
      case requestShape model of
        RequestField {label = value} : _ -> value
        [] -> "Input Text"

jsBool :: Bool -> String
jsBool value
  | value = "true"
  | otherwise = "false"

renderPursContractsModule :: RuntimeMode -> [ModelDescriptor] -> String
renderPursContractsModule runtimeMode models =
  unlines
    [ "module Generated.Contracts where",
      "",
      "type RequestField =",
      "  { name :: String",
      "  , label :: String",
      "  , fieldType :: String",
      "  }",
      "",
      "type ModelDescriptor =",
      "  { matrixRowId :: String",
      "  , modelId :: String",
      "  , displayName :: String",
      "  , family :: String",
      "  , description :: String",
      "  , artifactType :: String",
      "  , referenceModel :: String",
      "  , downloadUrl :: String",
      "  , selectedEngine :: String",
      "  , runtimeLane :: String",
      "  , requiresGpu :: Boolean",
      "  , notes :: String",
      "  , requestShape :: Array RequestField",
      "  }",
      "",
      "apiBasePath :: String",
      "apiBasePath = " <> show ("/api" :: String),
      "",
      "runtimeMode :: String",
      "runtimeMode = " <> show (Text.unpack (runtimeModeId runtimeMode)),
      "",
      "maxInlineOutputLength :: Int",
      "maxInlineOutputLength = 80",
      "",
      "models :: Array ModelDescriptor",
      "models =",
      "  ["
    ]
    <> intercalate ",\n" (map renderModel models)
    <> "\n  ]\n"
  where
    renderModel model =
      unlines
        [ "    { matrixRowId: " <> showText (matrixRowId model),
          "    , modelId: " <> showText (modelId model),
          "    , displayName: " <> showText (displayName model),
          "    , family: " <> showText (family model),
          "    , description: " <> showText (description model),
          "    , artifactType: " <> showText (artifactType model),
          "    , referenceModel: " <> showText (referenceModel model),
          "    , downloadUrl: " <> showText (downloadUrl model),
          "    , selectedEngine: " <> showText (selectedEngine model),
          "    , runtimeLane: " <> showText (runtimeLane model),
          "    , requiresGpu: " <> psBool (requiresGpu model),
          "    , notes: " <> showText (notes model),
          "    , requestShape: " <> renderRequestShape (requestShape model),
          "    }"
        ]
    renderRequestShape fields =
      "[ "
        <> intercalate ", " (map renderField fields)
        <> " ]"
    renderField RequestField {name = fieldName, label = fieldLabelValue, fieldType = fieldTypeValue} =
      "{ name: "
        <> showText fieldName
        <> ", label: "
        <> showText fieldLabelValue
        <> ", fieldType: "
        <> showText fieldTypeValue
        <> " }"
    showText = show . Text.unpack
    psBool True = "true"
    psBool False = "false"

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

ensureWebDependencies :: IO ()
ensureWebDependencies = do
  paths <- discoverPaths
  let webRoot = repoRoot paths </> "web"
  depsDirectoryPresent <- doesDirectoryExist (webRoot </> "node_modules")
  playwrightPresent <- doesFileExist (webRoot </> "node_modules" </> "playwright" </> "package.json")
  if depsDirectoryPresent && playwrightPresent
    then pure ()
    else runCommandInDirectory Nothing "npm" ["--prefix", "web", "ci"] (repoRoot paths)

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
      "  infernix service [--port PORT]",
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
      "  infernix internal generate-web-contracts PATH",
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
    [ "infernix internal generate-web-contracts PATH",
      "infernix internal generate-purs-contracts PATH",
      "infernix internal discover images RENDERED_CHART",
      "infernix internal discover claims RENDERED_CHART",
      "infernix internal discover harbor-overlay OVERLAY",
      "infernix internal publish-chart-images RENDERED_CHART OUTPUT",
      "infernix internal demo-config load PATH",
      "infernix internal demo-config validate PATH"
    ]
