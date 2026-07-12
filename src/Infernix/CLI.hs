{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.CLI
  ( main,
    writeGeneratedPursContracts,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, catch, evaluate, finally, throwIO, try)
import Control.Monad (unless, when)
import Data.Aeson (Value (..), eitherDecode, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.List qualified as List
import Data.Text qualified as Text
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.Cluster
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.CommandRegistry
import Infernix.Config
import Infernix.DemoConfig
  ( decodeDemoConfigFile,
    materializeEmptyModelsDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    renderModelListing,
    validateDemoConfigFile,
  )
import Infernix.DhallSchema (renderDhallSchema)
import Infernix.Engines.AppleSilicon (materializeMetalEngines, metalEngineArtifactAdapterIds)
import Infernix.Engines.LinuxNative (linuxNativeEngineArtifactAdapterIds, materializeLinuxNativeEngines)
import Infernix.Error (InfernixError (EdgePortNotPublished))
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostPrereqs (ensureAppleHostPrerequisites)
import Infernix.HostTools (HostTool (..))
import Infernix.HostTools qualified as HostTools
import Infernix.Lint.Chart (runChartLint)
import Infernix.Lint.Docs (runDocsLint)
import Infernix.Lint.Files (runFilesLint)
import Infernix.Lint.Proto (runProtoLint)
import Infernix.Models (expectedDaemonLocationForRuntime, expectedInferenceDispatchModeForRuntime, expectedInferenceExecutorLocationForRuntime)
import Infernix.ProjectInit (runProjectInit, runTestInit)
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
    RuntimeMode (AppleSilicon),
    runtimeModeId,
  )
import Infernix.Web.Contracts qualified as Contracts
import Infernix.Workflow
  ( ensureWebDependencies,
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
    doesFileExist,
    getPermissions,
    removeFile,
    removePathForcibly,
    renameFile,
    setPermissions,
  )
import System.Environment (getArgs, getExecutablePath)
import System.Exit (ExitCode (ExitSuccess), exitFailure, exitWith)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.Process (CreateProcess (cwd, env), createProcess, proc, readCreateProcessWithExitCode, terminateProcess, waitForProcess)

main :: IO ()
main = do
  setLocaleEncoding utf8
  syncBuildRootExecutable
  args <- getArgs
  case parseCommand args of
    Left _ -> do
      putStrLn helpText
      exitFailure
    Right command -> do
      validateCommandExecutionContext command
      ensureAppleHostPrerequisites (commandRuntimeMode command) command
      dispatch command

dispatch :: Command -> IO ()
dispatch command =
  case command of
    ShowRootHelp -> putStrLn helpText
    ShowTopicHelp topic -> putStrLn (topicHelpText topic)
    InitCommand maybeRuntimeMode maybeDemoUi force ifMissing -> runProjectInit maybeRuntimeMode maybeDemoUi force ifMissing
    TestInitCommand maybeRuntimeMode maybeDemoUi -> runTestInit maybeRuntimeMode maybeDemoUi
    ServiceCommand maybeRole maybeEngineName maybeConfigPath -> runService Nothing maybeRole (Text.pack <$> maybeEngineName) maybeConfigPath
    ClusterUpCommand -> clusterUp Nothing
    ClusterDownCommand -> clusterDown Nothing
    ClusterStatusCommand -> clusterStatus Nothing
    CacheStatusCommand -> runCacheStatus Nothing
    CacheEvictCommand maybeModelId -> runCacheEvict Nothing (Text.pack <$> maybeModelId)
    CacheRebuildCommand maybeModelId -> runCacheRebuild Nothing (Text.pack <$> maybeModelId)
    KubectlCommand kubectlArgs -> runKubectlCompat kubectlArgs
    DocsCheckCommand -> runDocsLint
    LintFilesCommand -> runFilesLint
    LintDocsCommand -> runDocsLint
    LintProtoCommand -> runProtoLint
    LintChartCommand -> runChartLint
    TestLintCommand -> runLint Nothing
    TestUnitCommand -> do
      ensureWebDependencies
      ensurePythonAdapterDependencies Nothing
      runCabalCommand Nothing ["test", "infernix-unit"]
      runWebNpmCommand Nothing ["--prefix", "web", "run", "test:unit"]
    TestIntegrationCommand ->
      withTestHarnessConfig (runClusterOwnedValidation Nothing (runCabalCommand Nothing ["test", "infernix-integration"]))
    TestE2ECommand ->
      withTestHarnessConfig (runClusterOwnedValidation Nothing (runEndToEnd Nothing))
    TestAllCommand ->
      withTestHarnessConfig $ do
        ensureWebDependencies
        runLint Nothing
        ensurePythonAdapterDependencies Nothing
        runCabalCommand Nothing ["test", "infernix-unit"]
        runWebNpmCommand Nothing ["--prefix", "web", "run", "test:unit"]
        runClusterOwnedValidation Nothing (runCabalCommand Nothing ["test", "infernix-integration"])
        runClusterOwnedValidation Nothing (runEndToEnd Nothing)
    InternalDiscoverImagesCommand renderedChartPath ->
      mapM_ putStrLn =<< discoverChartImagesFile renderedChartPath
    InternalDiscoverClaimsCommand renderedChartPath ->
      mapM_ (putStrLn . renderPersistentClaimLine) =<< discoverChartClaimsFile renderedChartPath
    InternalDiscoverHarborOverlayCommand overlayPath ->
      mapM_ putStrLn =<< discoverHarborOverlayImageRefsFile overlayPath
    InternalPublishChartImagesCommand renderedChartPath outputPath -> do
      paths <- discoverPaths
      PublishImages.publishChartImagesFile (harborPublishOptionsForPaths paths) (\_ -> pure Nothing) renderedChartPath outputPath
    InternalMaterializeSubstrateCommand runtimeMode demoUiEnabledValue emptyModels -> do
      paths <- discoverPaths
      ensureRepoLayout paths
      materializedPath <-
        if emptyModels
          then materializeEmptyModelsDemoConfigFile paths runtimeMode demoUiEnabledValue
          else materializeGeneratedDemoConfigFile paths runtimeMode demoUiEnabledValue
      hostManifestPath <- materializeHostManifestFile paths
      putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
      putStrLn ("demoUiEnabled: " <> show demoUiEnabledValue)
      putStrLn ("emptyModels: " <> show emptyModels)
      putStrLn ("generatedDemoConfigPath: " <> materializedPath)
      putStrLn ("hostManifestPath: " <> hostManifestPath)
    InternalMaterializeMetalEnginesCommand -> do
      paths <- discoverPaths
      ensureRepoLayout paths
      materializeMetalEngines paths
      mapM_ (putStrLn . ("metalEngineArtifact: " <>) . Text.unpack) metalEngineArtifactAdapterIds
    InternalMaterializeLinuxNativeEnginesCommand -> do
      materializeLinuxNativeEngines
      mapM_ (putStrLn . ("linuxNativeEngineArtifact: " <>) . Text.unpack) linuxNativeEngineArtifactAdapterIds
    InternalDemoConfigLoadCommand demoConfigPath -> do
      demoConfig <- decodeDemoConfigFile demoConfigPath
      putStr (renderModelListing demoConfig)
    InternalDemoConfigValidateCommand demoConfigPath ->
      validateDemoConfigFile demoConfigPath
    InternalDhallSchemaCommand schema ->
      case renderDhallSchema schema of
        Left err -> ioError (userError err)
        Right schemaText -> putStr (Text.unpack schemaText)
    InternalGeneratePursContractsCommand outputDir -> do
      runtimeMode <- resolveRuntimeMode Nothing
      writeGeneratedPursContracts runtimeMode outputDir
    InternalPulsarRoundTripCommand demoConfigPath modelIdValue inputTextValue -> do
      demoConfig <- decodeDemoConfigFile demoConfigPath
      runInternalPulsarRoundTrip (configRuntimeMode demoConfig) demoConfigPath modelIdValue inputTextValue

commandRuntimeMode :: Command -> Maybe RuntimeMode
commandRuntimeMode command =
  case command of
    InternalMaterializeSubstrateCommand runtimeMode _ _ -> Just runtimeMode
    _ -> Nothing

validateCommandExecutionContext :: Command -> IO ()
validateCommandExecutionContext command = do
  paths <- discoverPaths
  maybeRuntimeMode <- runtimeModeForCommand command
  maybe (pure ()) (ensureSupportedRuntimeModeForExecutionContext paths) maybeRuntimeMode
  where
    runtimeModeForCommand selectedCommand =
      case selectedCommand of
        ServiceCommand {} -> activeRuntimeMode
        ClusterUpCommand -> activeRuntimeMode
        ClusterDownCommand -> activeRuntimeMode
        ClusterStatusCommand -> activeRuntimeMode
        CacheStatusCommand -> activeRuntimeMode
        CacheEvictCommand _ -> activeRuntimeMode
        CacheRebuildCommand _ -> activeRuntimeMode
        KubectlCommand _ -> activeRuntimeMode
        TestLintCommand -> activeRuntimeMode
        TestUnitCommand -> activeRuntimeMode
        TestIntegrationCommand -> activeRuntimeMode
        TestE2ECommand -> activeRuntimeMode
        TestAllCommand -> activeRuntimeMode
        InternalMaterializeSubstrateCommand runtimeMode _ _ -> pure (Just runtimeMode)
        InternalGeneratePursContractsCommand _ -> activeRuntimeMode
        _ -> pure Nothing
    activeRuntimeMode = Just <$> ensureActiveSubstrateFile

-- | Phase 1 Sprint 1.11 — discover the active substrate by reading the
-- staged @infernix-substrate.dhall@ file under the launcher build root.
-- The supported contract has no env-var fallback: on the Linux outer-
-- container path the launcher image bakes the substrate file at image
-- build time (the Dockerfile invokes @infernix internal
-- materialize-substrate@ with an explicit substrate argument). On Apple
-- host-native, the execution context itself fixes the active substrate to
-- @apple-silicon@ so lifecycle commands can materialize the file before
-- cluster work. When the file is absent on paths that require a staged
-- payload, 'configuredRuntimeMode' surfaces a typed diagnostic that names
-- the supported materialization helpers.
ensureActiveSubstrateFile :: IO RuntimeMode
ensureActiveSubstrateFile = do
  paths <- discoverPaths
  ensureRepoLayout paths
  runtimeMode <- configuredRuntimeMode paths
  ensureSupportedRuntimeModeForExecutionContext paths runtimeMode
  pure runtimeMode

configuredRuntimeMode :: Paths -> IO RuntimeMode
configuredRuntimeMode = targetRuntimeModeForExecutionContext

harborPublishOptionsForPaths :: Paths -> PublishImages.HarborPublishOptions
harborPublishOptionsForPaths paths =
  PublishImages.defaultHarborPublishOptions
    { PublishImages.harborDockerCommand = hostToolPathOrName paths HostDocker,
      PublishImages.harborSkopeoCommand = hostToolPathOrName paths HostSkopeo
    }

hostToolPathOrName :: Paths -> HostTool -> FilePath
hostToolPathOrName paths tool =
  case pathsHostConfig paths of
    Just hostConfig ->
      let candidate = HostTools.hostToolPath hostConfig tool
       in if Text.null candidate
            then fallbackPathOrName
            else Text.unpack candidate
    Nothing -> fallbackPathOrName
  where
    fallbackPathOrName =
      case HostTools.hostToolFallbackPath tool of
        Just path -> path
        Nothing -> Text.unpack (HostTools.hostToolName tool)

runLint :: Maybe RuntimeMode -> IO ()
runLint maybeRuntimeMode = do
  runCabalCommand maybeRuntimeMode ["test", "infernix-haskell-style"]
  runFilesLint
  runChartLint
  runProtoLint
  runDocsLint
  runPythonQualityIfPresent maybeRuntimeMode
  runCabalCommand maybeRuntimeMode ["build", "all"]

runClusterOwnedValidation :: Maybe RuntimeMode -> IO a -> IO a
runClusterOwnedValidation maybeRuntimeMode action = do
  clusterDown maybeRuntimeMode
  action
    `finally` clusterDown maybeRuntimeMode

-- | Phase 8 Sprint 8.6: the test harness owns @./infernix.dhall@ for the
-- duration of a run. It reads @./infernix.test.dhall@ (failing fast with an
-- @infernix test init@ reminder when it is absent), takes ownership of
-- @./infernix.dhall@ by moving any existing config (an operator @infernix
-- init@ config, or the image-baked empty-models config) to a backup, generates
-- the harness config from the test config's substrate + demo-ui selection, runs
-- the suites, and then restores the backup (or removes the generated file when
-- there was none). The integration suite's per-variant @internal
-- materialize-substrate@ keeps rewriting this same harness-owned path during
-- the run. Back-up/restore (rather than a hard refuse) is what lets the
-- supported container @infernix test all@ run against an image that bakes
-- @./infernix.dhall@ for the @cluster up@ path, while still protecting an
-- operator's host config.
withTestHarnessConfig :: IO a -> IO a
withTestHarnessConfig action = do
  paths <- discoverPaths
  ensureRepoLayout paths
  let testConfig = testConfigPath paths
      runtimeConfig = runtimeConfigPath paths
      backupConfig = runtimeConfig <> ".harness-backup"
  testConfigExists <- doesFileExist testConfig
  unless testConfigExists $
    ioError
      ( userError
          ( "test config missing at "
              <> testConfig
              <> "; run `infernix test init` to create it"
          )
      )
  hadExistingRuntimeConfig <- doesFileExist runtimeConfig
  when hadExistingRuntimeConfig (renameFile runtimeConfig backupConfig)
  testDemoConfig <- decodeDemoConfigFile testConfig
  _ <-
    materializeGeneratedDemoConfigFile
      paths
      (configRuntimeMode testDemoConfig)
      (demoUiEnabled testDemoConfig)
  action `finally` restoreRuntimeConfig runtimeConfig backupConfig hadExistingRuntimeConfig

-- | Restore the pre-run @./infernix.dhall@ after a harness run: remove the
-- harness-generated file (and any per-variant rewrite), then move the backup
-- back into place when one was taken.
restoreRuntimeConfig :: FilePath -> FilePath -> Bool -> IO ()
restoreRuntimeConfig runtimeConfig backupConfig hadExistingRuntimeConfig = do
  present <- doesFileExist runtimeConfig
  when present (removeFile runtimeConfig)
  when hadExistingRuntimeConfig $ do
    backupPresent <- doesFileExist backupConfig
    when backupPresent (renameFile backupConfig runtimeConfig)

runEndToEnd :: Maybe RuntimeMode -> IO ()
runEndToEnd maybeRuntimeMode = do
  paths <- discoverPaths
  runtimeModes <-
    case maybeRuntimeMode of
      Just runtimeMode -> pure [runtimeMode]
      Nothing -> (: []) <$> resolveRuntimeMode Nothing
  mapM_ (runRuntimeModeE2E paths) runtimeModes

runRuntimeModeE2E :: Paths -> RuntimeMode -> IO ()
runRuntimeModeE2E paths runtimeMode =
  ( do
      clusterUp (Just runtimeMode)
      let expectedInferenceDispatchMode = Text.unpack (expectedInferenceDispatchModeForRuntime runtimeMode)
      maybePort <- readEdgePortMaybe paths
      edgePort <-
        case maybePort of
          Just port -> pure port
          Nothing -> throwIO EdgePortNotPublished
      let expectedDaemonLocation = Text.unpack (expectedDaemonLocationForRuntime runtimeMode)
          expectedInferenceExecutorLocation = Text.unpack (expectedInferenceExecutorLocationForRuntime runtimeMode)
      withRuntimeServiceDaemonIfNeeded paths runtimeMode $
        case controlPlaneContext paths of
          HostNative ->
            runHostNativePlaywright
              paths
              runtimeMode
              edgePort
              expectedDaemonLocation
              expectedInferenceExecutorLocation
              expectedInferenceDispatchMode
              "cluster-demo"
          OuterContainer ->
            runInContainerPlaywright
              paths
              runtimeMode
              (kindControlPlaneNodeName paths runtimeMode)
              30090
              expectedDaemonLocation
              expectedInferenceExecutorLocation
              expectedInferenceDispatchMode
              "cluster-demo"
  )
    `finally` clusterDown (Just runtimeMode)

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
            inputText = Text.pack inputTextValue,
            inputObjectRef = Nothing,
            requestUserId = Nothing,
            requestContextId = Nothing
          }
  requestIdValue <- publishInferenceRequest paths runtimeMode requestTopicValue requestValue
  maybeResult <- waitForInternalPulsarResult paths runtimeMode (resultTopic demoConfig) requestIdValue
  case maybeResult of
    Nothing ->
      ioError
        ( userError
            ( "timed out waiting for Pulsar result for request "
                <> Text.unpack requestIdValue
            )
        )
    Just resultValue -> printInternalPulsarResult resultValue

waitForInternalPulsarResult :: Paths -> RuntimeMode -> Text.Text -> Text.Text -> IO (Maybe InferenceResult)
waitForInternalPulsarResult paths runtimeMode resultTopicValue requestIdValue = go (120 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 = pure Nothing
      | otherwise = do
          maybeResult <- readPublishedInferenceResultMaybe paths runtimeMode resultTopicValue requestIdValue
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
    ResultPayload {inferenceError = Just errorValue} ->
      putStrLn ("inferenceError: " <> show errorValue)
    _ -> pure ()

-- | Phase 3 Sprint 3.10 — invoke Playwright against the routed
-- surface using a typed JSON fixture at
-- @<runtimeRoot>/playwright-fixture.json@. On Linux this runs inside
-- the launcher container against Docker's private @kind@ network; on
-- Apple it runs host-native @npm exec@ against the published localhost
-- edge port. The fixture replaces the retired @INFERNIX_EDGE_PORT@ /
-- @INFERNIX_PLAYWRIGHT_*@ / @INFERNIX_EXPECT_*@ env-var family.
runHostNativePlaywright ::
  Paths ->
  RuntimeMode ->
  Int ->
  String ->
  String ->
  String ->
  String ->
  IO ()
runHostNativePlaywright paths runtimeMode =
  runPlaywrightWithFixture paths runtimeMode "127.0.0.1"

runInContainerPlaywright ::
  Paths ->
  RuntimeMode ->
  String ->
  Int ->
  String ->
  String ->
  String ->
  String ->
  IO ()
runInContainerPlaywright = runPlaywrightWithFixture

runPlaywrightWithFixture ::
  Paths ->
  RuntimeMode ->
  String ->
  Int ->
  String ->
  String ->
  String ->
  String ->
  IO ()
runPlaywrightWithFixture paths runtimeMode playwrightHost playwrightPort expectedDaemonLocation expectedInferenceExecutorLocation expectedInferenceDispatchMode expectedApiUpstreamMode = do
  waitForPlaywrightSurface paths playwrightHost playwrightPort expectedDaemonLocation expectedInferenceExecutorLocation expectedInferenceDispatchMode expectedApiUpstreamMode
  infernixExecutable <- getExecutablePath
  let fixturePath = runtimeRoot paths </> "playwright-fixture.json"
      fixturePayload =
        encode
          ( object
              [ Key.fromText "host" .= playwrightHost,
                Key.fromText "edgePort" .= playwrightPort,
                Key.fromText "repoRoot" .= repoRoot paths,
                Key.fromText "infernixCommand" .= infernixExecutable,
                Key.fromText "expectedDaemonLocation" .= expectedDaemonLocation,
                Key.fromText "expectedInferenceExecutorLocation" .= expectedInferenceExecutorLocation,
                Key.fromText "expectedInferenceDispatchMode" .= expectedInferenceDispatchMode,
                Key.fromText "expectedApiUpstreamMode" .= expectedApiUpstreamMode
              ]
          )
  createDirectoryIfMissing True (runtimeRoot paths)
  LazyChar8.writeFile fixturePath fixturePayload
  runWebNpmCommand (Just runtimeMode) ["--prefix", "web", "exec", "--", "playwright", "test", "--config", "web/playwright.config.js"]

waitForPlaywrightSurface :: Paths -> String -> Int -> String -> String -> String -> String -> IO ()
waitForPlaywrightSurface paths host edgePort expectedDaemonLocation expectedInferenceExecutorLocation expectedInferenceDispatchMode expectedApiUpstreamMode = go (60 :: Int)
  where
    go remainingAttempts
      | remainingAttempts <= 0 =
          ioError
            ( userError
                ( "timed out waiting for routed surface at "
                    <> host
                    <> ":"
                    <> show edgePort
                    <> " to serve publication and demo-config traffic"
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
      maybePublication <- loadJsonUrl paths (baseUrl <> "/api/publication")
      maybeDemoConfig <- loadJsonUrl paths (baseUrl <> "/api/demo-config")
      maybeHome <- loadTextUrl paths (baseUrl <> "/")
      case (maybePublication, maybeDemoConfig, maybeHome) of
        (Just publicationPayload, Just _demoConfigPayload, Just homeBody) ->
          pure
            ( jsonTextAt ["daemonLocation"] publicationPayload == Just (Text.pack expectedDaemonLocation)
                && jsonTextAt ["inferenceExecutorLocation"] publicationPayload == Just (Text.pack expectedInferenceExecutorLocation)
                && jsonTextAt ["inferenceDispatchMode"] publicationPayload == Just (Text.pack expectedInferenceDispatchMode)
                && jsonTextAt ["apiUpstream", "mode"] publicationPayload == Just (Text.pack expectedApiUpstreamMode)
                && "Infernix" `isInfixOf` homeBody
            )
        _ -> pure False

runCacheStatus :: Maybe RuntimeMode -> IO ()
runCacheStatus maybeRuntimeMode = do
  paths <- discoverPaths
  runtimeMode <- resolveRuntimeMode maybeRuntimeMode
  manifests <- listCacheManifests paths runtimeMode
  putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("cacheRoot: " <> modelCacheRoot paths </> Text.unpack (runtimeModeId runtimeMode))
  putStrLn ("cacheManifestCount: " <> show (length manifests))
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

withRuntimeServiceDaemonIfNeeded :: Paths -> RuntimeMode -> IO a -> IO a
withRuntimeServiceDaemonIfNeeded paths runtimeMode action =
  case (controlPlaneContext paths, runtimeMode) of
    (HostNative, AppleSilicon) -> withRuntimeServiceDaemon paths action
    _ -> action

withRuntimeServiceDaemon :: Paths -> IO a -> IO a
withRuntimeServiceDaemon paths action = do
  infernixExecutable <- getExecutablePath
  (_, _, _, processHandle) <-
    createProcess
      (proc infernixExecutable ["service"])
        { cwd = Just (repoRoot paths)
        }
  action
    `finally` do
      terminateProcess processHandle
      _ <- waitForProcess processHandle
      pure ()

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
runCabalCommand maybeRuntimeMode = runCommand maybeRuntimeMode "cabal"

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
  removePathForcibly tempGeneratedRoot `catch` (\(_ :: IOException) -> pure ())
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
      | line == "import Prim (Array, Boolean, Number, String)" = "import Prim (Array, Boolean, Int, Number, String)"
      | line == "import Data.Newtype (class Newtype)" =
          unlines
            [ "import Data.Newtype (class Newtype)",
              "import Foreign (ForeignError(..), fail) as Foreign",
              "import Simple.JSON as JSON"
            ]
      | otherwise = line

    keepLine line =
      not
        ( "import Data.Generic.Rep " `isPrefixOf` line
            || "import Data.Generic " `isPrefixOf` line
            || "derive instance generic" `isPrefixOf` line
        )

runCommand :: Maybe RuntimeMode -> FilePath -> [String] -> IO ()
runCommand maybeRuntimeMode command args = do
  paths <- discoverCliCommandPaths
  runCommandWithCwdAndEnvRemovingWithPaths paths maybeRuntimeMode [] [] command args (repoRoot paths)

runCommandWithCwdAndEnv :: Maybe RuntimeMode -> [(String, String)] -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwdAndEnv maybeRuntimeMode extraEnvironment command args workingDirectory = do
  paths <- discoverCliCommandPaths
  runCommandWithCwdAndEnvRemovingWithPaths paths maybeRuntimeMode [] extraEnvironment command args workingDirectory

runCommandWithCwdAndEnvRemovingWithPaths :: Paths -> Maybe RuntimeMode -> [String] -> [(String, String)] -> FilePath -> [String] -> FilePath -> IO ()
runCommandWithCwdAndEnvRemovingWithPaths paths _maybeRuntimeMode removedEnvironmentNames extraEnvironment command args workingDirectory = do
  resolvedCommand <- resolveCliCommandWithPaths paths command
  let augmentedEnvironment =
        mergeEnvironment
          extraEnvironment
          (removeEnvironmentVariables removedEnvironmentNames (cliSubprocessBaseEnvFor paths))
  (_, _, _, processHandle) <-
    createProcess
      (proc resolvedCommand args)
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

discoverCliCommandPaths :: IO Paths
discoverCliCommandPaths = do
  paths <- discoverPaths
  requireHostManifest paths
  pure paths

resolveCliCommandWithPaths :: Paths -> FilePath -> IO FilePath
resolveCliCommandWithPaths paths command =
  case hostToolForCliCommand command of
    Just tool -> resolveCliHostTool paths tool
    Nothing -> pure command

hostToolForCliCommand :: FilePath -> Maybe HostTool
hostToolForCliCommand command =
  case command of
    "cabal" -> Just HostCabal
    "npm" -> Just HostNpm
    "node" -> Just HostNode
    "curl" -> Just HostCurl
    "poetry" -> Just HostPoetry
    "python3" -> Just HostPython3
    "git" -> Just HostGit
    "protoc" -> Just HostProtoc
    _ -> Nothing

resolveCliHostTool :: Paths -> HostTool -> IO FilePath
resolveCliHostTool paths tool =
  case pathsHostConfig paths of
    Just hostConfig -> do
      let configured = HostTools.hostToolPath hostConfig tool
      if Text.null configured
        then fallbackOrFail
        else pure (Text.unpack configured)
    Nothing -> fallbackOrFail
  where
    fallbackOrFail = do
      maybeFallback <- firstExistingPath (HostTools.hostToolFallbackCandidates tool)
      case maybeFallback of
        Just path -> pure path
        Nothing ->
          ioError
            ( userError
                ( "required host tool is unavailable: "
                    <> Text.unpack (HostTools.hostToolName tool)
                )
            )

captureCliHostTool :: Paths -> HostTool -> [String] -> IO String
captureCliHostTool paths tool args = do
  command <- resolveCliHostTool paths tool
  (exitCode, stdoutOutput, stderrOutput) <-
    readCreateProcessWithExitCode
      (proc command args)
        { env = Just (cliSubprocessBaseEnvFor paths)
        }
      ""
  case exitCode of
    ExitSuccess -> pure stdoutOutput
    _ -> ioError (userError stderrOutput)

cliSubprocessBaseEnvFor :: Paths -> [(String, String)]
cliSubprocessBaseEnvFor paths =
  maybe [] hostHomeEnv (pathsHostConfig paths)
    <> [ ("PATH", cliSubprocessSearchPath paths),
         ("LANG", "C.UTF-8"),
         ("LC_ALL", "C.UTF-8")
       ]

hostHomeEnv :: HostConfig.HostConfig -> [(String, String)]
hostHomeEnv hostConfig =
  let home = Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem hostConfig))
   in [("HOME", home) | not (null home)]

cliSubprocessSearchPath :: Paths -> String
cliSubprocessSearchPath paths =
  let fallback =
        [ "/opt/homebrew/bin",
          "/usr/local/bin",
          "/usr/bin",
          "/bin"
        ]
      manifestDirs =
        maybe [] cliHostToolParentDirs (pathsHostConfig paths)
   in List.intercalate ":" (List.nub (manifestDirs <> fallback))

cliHostToolParentDirs :: HostConfig.HostConfig -> [FilePath]
cliHostToolParentDirs hostConfig =
  List.nub
    [ takeDirectory path
    | tool <-
        [ HostCabal,
          HostGhc,
          HostGhcup,
          HostNpm,
          HostNode,
          HostCurl,
          HostPython3,
          HostPoetry,
          HostGit,
          HostProtoc,
          HostOrmolu,
          HostHlint
        ],
      let path = Text.unpack (HostTools.hostToolPath hostConfig tool),
      not (null path)
    ]

firstExistingPath :: [FilePath] -> IO (Maybe FilePath)
firstExistingPath [] = pure Nothing
firstExistingPath (candidate : rest) = do
  present <- doesFileExist candidate
  if present
    then pure (Just candidate)
    else firstExistingPath rest

loadJsonUrl :: Paths -> String -> IO (Maybe Value)
loadJsonUrl paths url = do
  response <- loadTextUrl paths url
  case response of
    Nothing -> pure Nothing
    Just payload ->
      case eitherDecode (LazyChar8.pack payload) of
        Left _ -> pure Nothing
        Right decodedValue -> pure (Just decodedValue)

loadTextUrl :: Paths -> String -> IO (Maybe String)
loadTextUrl paths url = do
  response <- try (captureCliHostTool paths HostCurl ["-fsS", url]) :: IO (Either IOException String)
  case response of
    Left _ -> pure Nothing
    Right payload -> pure (Just payload)

jsonTextAt :: [Text.Text] -> Value -> Maybe Text.Text
jsonTextAt [] value = valueText value
jsonTextAt (segment : remainingSegments) (Object objectValue) =
  KeyMap.lookup (Key.fromText segment) objectValue >>= jsonTextAt remainingSegments
jsonTextAt _ _ = Nothing

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
    ensurePoetryProjectReady paths projectDirectory
    poetryExecutable <- ensurePoetryExecutable paths
    runCommandWithCwdAndEnv
      maybeRuntimeMode
      []
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
    ensurePoetryProjectReady paths projectDirectory

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
