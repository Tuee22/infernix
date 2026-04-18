{-# LANGUAGE OverloadedStrings #-}

module Infernix.CLI
  ( main,
    extractRuntimeMode,
  )
where

import Control.Concurrent (threadDelay)
import Control.Exception (finally)
import Control.Monad (forM_, when)
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
    RuntimeMode,
    allRuntimeModes,
    parseRuntimeMode,
    runtimeModeId,
  )
import System.Directory
  ( copyFile,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    findExecutable,
    getPermissions,
    setPermissions,
  )
import System.Environment (getArgs, getEnvironment, getExecutablePath)
import System.Exit (ExitCode (ExitSuccess), exitFailure, exitWith)
import System.FilePath (takeDirectory, (</>))
import System.Info (os)
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
  _ -> do
    ensureAppleHostPrerequisites
    case args of
      ["service"] -> runService maybeRuntimeMode Nothing
      ["service", "--port", port] -> runService maybeRuntimeMode (Just (read port))
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
      ["internal", "generate-web-contracts", outputDir] -> do
        runtimeMode <- resolveRuntimeMode maybeRuntimeMode
        writeGeneratedContracts runtimeMode outputDir
      _ -> do
        putStrLn helpText
        exitFailure

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
  let runtimeModes = maybe allRuntimeModes pure maybeRuntimeMode
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
            runPlaywrightImage runtimeMode edgePort "control-plane-host" "host-daemon-bridge"
        else
          runPlaywrightImage runtimeMode edgePort "cluster-pod" "cluster-service"
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

runPlaywrightImage :: RuntimeMode -> Int -> String -> String -> IO ()
runPlaywrightImage runtimeMode edgePort expectedDaemonLocation expectedApiUpstreamMode = do
  paths <- discoverPaths
  imageRef <- resolvePlaywrightImage paths runtimeMode
  runCommand
    (Just runtimeMode)
    "docker"
    [ "run",
      "--rm",
      "--add-host",
      "host.docker.internal:host-gateway",
      "-e",
      "INFERNIX_RUNTIME_MODE=" <> Text.unpack (runtimeModeId runtimeMode),
      "-e",
      "INFERNIX_EDGE_PORT=" <> show edgePort,
      "-e",
      "INFERNIX_PLAYWRIGHT_HOST=host.docker.internal",
      "-e",
      "INFERNIX_EXPECT_DAEMON_LOCATION=" <> expectedDaemonLocation,
      "-e",
      "INFERNIX_EXPECT_API_UPSTREAM_MODE=" <> expectedApiUpstreamMode,
      imageRef,
      "npm",
      "run",
      "test:e2e:image"
    ]

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
runCommandWithCwd maybeRuntimeMode command args workingDirectory = do
  environment <- getEnvironment
  let augmentedEnvironment =
        case maybeRuntimeMode of
          Nothing -> environment
          Just runtimeMode ->
            ("INFERNIX_RUNTIME_MODE", Text.unpack (runtimeModeId runtimeMode))
              : filter ((/= "INFERNIX_RUNTIME_MODE") . fst) environment
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
ensureAppleHostPrerequisites = do
  paths <- discoverPaths
  when (controlPlaneContext paths == "host-native" && os == "darwin") $ do
    ensureHostCommand "python3" Nothing
    manifests <- discoverPythonDependencyManifests (repoRoot paths)
    when (any requiresPoetry manifests) (ensureHostCommand "poetry" (Just installPoetryWithBrew))
    forM_ manifests installPythonDependencyManifest

data PythonDependencyManifest
  = PoetryProject FilePath
  | RequirementsFile FilePath

discoverPythonDependencyManifests :: FilePath -> IO [PythonDependencyManifest]
discoverPythonDependencyManifests repoRootPath = do
  let poetryCandidates =
        [ repoRootPath </> "pyproject.toml",
          repoRootPath </> "tools" </> "pyproject.toml"
        ]
      requirementsCandidates =
        [ repoRootPath </> "requirements.txt",
          repoRootPath </> "tools" </> "requirements.txt"
        ]
  poetryManifests <- collectManifests PoetryProject poetryCandidates
  requirementsManifests <- collectManifests RequirementsFile requirementsCandidates
  pure (poetryManifests <> requirementsManifests)
  where
    collectManifests constructor candidates = do
      present <- mapM doesFileExist candidates
      pure [constructor candidate | (candidate, True) <- zip candidates present]

requiresPoetry :: PythonDependencyManifest -> Bool
requiresPoetry manifest = case manifest of
  PoetryProject _ -> True
  RequirementsFile _ -> False

installPythonDependencyManifest :: PythonDependencyManifest -> IO ()
installPythonDependencyManifest manifest = case manifest of
  PoetryProject manifestPath ->
    runCommandInDirectory Nothing "poetry" ["install", "--no-root"] (takeDirectory manifestPath)
  RequirementsFile manifestPath ->
    runCommand
      Nothing
      "python3"
      ["-m", "pip", "install", "--quiet", "--disable-pip-version-check", "--user", "--break-system-packages", "-r", manifestPath]

ensureHostCommand :: FilePath -> Maybe (IO ()) -> IO ()
ensureHostCommand commandName maybeInstall = do
  maybeCommand <- findExecutable commandName
  case maybeCommand of
    Just _ -> pure ()
    Nothing ->
      case maybeInstall of
        Nothing -> ioError (userError (commandName <> " is required on the Apple host path but is not installed."))
        Just installAction -> do
          installAction
          maybeInstalledCommand <- findExecutable commandName
          case maybeInstalledCommand of
            Just _ -> pure ()
            Nothing ->
              ioError
                (userError (commandName <> " was not found after the attempted host prerequisite installation."))

installPoetryWithBrew :: IO ()
installPoetryWithBrew = do
  maybeBrew <- findExecutable "brew"
  case maybeBrew of
    Nothing ->
      ioError
        (userError "poetry is required by the repo-owned Python dependency manifests, but Homebrew is not installed on the Apple host path.")
    Just _ -> runCommand Nothing "brew" ["install", "poetry"]

syncBuildRootExecutable :: IO ()
syncBuildRootExecutable = do
  paths <- discoverPaths
  ensureRepoLayout paths
  currentExecutable <- getExecutablePath
  let targetExecutable = buildRoot paths </> "infernix"
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
      "  infernix cluster up",
      "  infernix cluster down",
      "  infernix cluster status",
      "  infernix cache status",
      "  infernix cache evict [--model MODEL_ID]",
      "  infernix cache rebuild [--model MODEL_ID]",
      "  infernix kubectl ...",
      "  infernix test lint",
      "  infernix test unit",
      "  infernix test integration",
      "  infernix test e2e",
      "  infernix test all",
      "  infernix docs check"
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
