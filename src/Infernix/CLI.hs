{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.CLI
  ( main,
    writeGeneratedPursContracts,
    RuntimeConfigRestorePlan,
    runtimeConfigRestorePlan,
  )
where

import Control.Applicative ((<|>))
import Control.Exception (IOException, catch, evaluate, mask, throwIO, try)
import Control.Monad (unless, void, when)
import Data.Aeson (Value (..), eitherDecode, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.Foldable (for_)
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.List qualified as List
import Data.Text qualified as Text
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.BuildMemory
  ( ToolchainInvocation (ToolchainBuildAll, ToolchainTest),
    ToolchainSpawnAuthority,
    ToolchainTestSuite (HaskellStyleSuite, IntegrationSuite, UnitSuite),
  )
import Infernix.BuildMemory qualified as BuildMemory
import Infernix.Cluster
import Infernix.Cluster.Discover
import Infernix.Cluster.PublishImages qualified as PublishImages
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.CommandRegistry
import Infernix.Config
import Infernix.DemoConfig
  ( materializeBuildMemoryCeilingFile,
    materializeEmptyModelsDemoConfigFile,
    materializeGeneratedDemoConfigFile,
    materializeHostManifestFile,
    renderModelListing,
  )
import Infernix.DemoConfig.Internal (decodeDemoConfigFile)
import Infernix.DescriptorSpace (establishBoundedDescriptorSpace)
import Infernix.DhallSchema (renderDhallSchema)
import Infernix.Engines.AppleSilicon (materializeMetalEngines, metalEngineArtifactAdapterIds)
import Infernix.Engines.LinuxNative (linuxNativeEngineArtifactAdapterIds, materializeLinuxNativeEngines)
import Infernix.Error
  ( InfernixError (EdgePortNotPublished),
    bracketPreservingPrimary,
    finallyPreservingPrimary,
    runCleanupsPreservingFailures,
  )
import Infernix.Evidence.Readiness qualified as Readiness
import Infernix.ExecutionPlan qualified as ExecutionPlan
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostMemory qualified as HostMemory
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
import Infernix.Substrate (decodeCompiledRuntimePlanFile)
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
import System.Process (CreateProcess (cwd, env), createProcess, getPid, proc, readCreateProcessWithExitCode, terminateProcess, waitForProcess)
import System.Timeout (timeout)

main :: IO ()
main = do
  -- Before the internal self-exec dispatch, because those images spawn too,
  -- and before anything opens a descriptor, which is what makes the bound
  -- sound rather than merely cheap. See "Infernix.DescriptorSpace".
  _ <- establishBoundedDescriptorSpace
  dispatchInternalSubprocessMode
  setLocaleEncoding utf8
  syncBuildRootExecutable
  args <- getArgs
  case parseCommand args of
    Left _ -> do
      putStrLn helpText
      exitFailure
    Right command -> do
      reconcileInterruptedHarnessState
      resolvedRuntimeMode <- validateCommandExecutionContext command
      ensureAppleHostPrerequisites resolvedRuntimeMode command
      dispatch command

dispatchInternalSubprocessMode :: IO ()
dispatchInternalSubprocessMode =
  Subprocess.dispatchInternalSubprocessMode

dispatch :: Command -> IO ()
dispatch command =
  case command of
    ShowRootHelp -> putStrLn helpText
    ShowTopicHelp topic -> putStrLn (topicHelpText topic)
    InitCommand maybeRuntimeMode maybeDemoUi force ifMissing ->
      withRuntimeConfigWriteAccess
        (runProjectInit maybeRuntimeMode maybeDemoUi force ifMissing)
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
      withToolchainAuthority $ \authority ->
        runToolchainCommand authority Nothing (ToolchainTest UnitSuite)
      runWebNpmCommand Nothing ["--prefix", "web", "run", "test:unit"]
    TestIntegrationCommand ->
      runClusterOwnedValidation
        Nothing
        ( withTestHarnessConfig
            ( withToolchainAuthority $ \authority ->
                runToolchainCommand authority Nothing (ToolchainTest IntegrationSuite)
            )
        )
    TestE2ECommand ->
      runClusterOwnedValidation
        Nothing
        (withTestHarnessConfig (runEndToEnd Nothing))
    TestAllCommand -> do
      ensureWebDependencies
      runLint Nothing
      ensurePythonAdapterDependencies Nothing
      withToolchainAuthority $ \authority ->
        runToolchainCommand authority Nothing (ToolchainTest UnitSuite)
      runWebNpmCommand Nothing ["--prefix", "web", "run", "test:unit"]
      runClusterOwnedValidation Nothing $
        withTestHarnessConfig $ do
          withToolchainAuthority $ \authority ->
            runToolchainCommand authority Nothing (ToolchainTest IntegrationSuite)
          runEndToEnd Nothing
    InternalDiscoverImagesCommand renderedChartPath ->
      mapM_ putStrLn =<< discoverChartImagesFile renderedChartPath
    InternalDiscoverClaimsCommand renderedChartPath ->
      mapM_ (putStrLn . renderPersistentClaimLine) =<< discoverChartClaimsFile renderedChartPath
    InternalDiscoverHarborOverlayCommand overlayPath ->
      mapM_ putStrLn =<< discoverHarborOverlayImageRefsFile overlayPath
    InternalPublishChartImagesCommand renderedChartPath outputPath ->
      PublishImages.publishChartImagesFile PublishImages.defaultHarborPublishOptions (\_ -> pure ()) renderedChartPath outputPath
    InternalMaterializeSubstrateCommand runtimeMode demoUiEnabledValue emptyModels ->
      withRuntimeConfigWriteAccess $ do
        paths <- discoverPaths
        ensureRepoLayout paths
        materializedPath <-
          if emptyModels
            then materializeEmptyModelsDemoConfigFile paths runtimeMode demoUiEnabledValue
            else materializeGeneratedDemoConfigFile paths runtimeMode demoUiEnabledValue
        hostManifestPath <- materializeHostManifestFile paths
        -- Phase 1 Sprint 1.21 — the launcher image builds this repository
        -- image-locally, so the image needs the same derived build ceiling an
        -- operator's `infernix init` writes. It is derived from the manifest
        -- just written, so it is written after it.
        buildCeilingPath <- materializeBuildMemoryCeilingFile paths
        putStrLn ("runtimeMode: " <> Text.unpack (runtimeModeId runtimeMode))
        putStrLn ("demoUiEnabled: " <> show demoUiEnabledValue)
        putStrLn ("emptyModels: " <> show emptyModels)
        putStrLn ("generatedDemoConfigPath: " <> materializedPath)
        putStrLn ("hostManifestPath: " <> hostManifestPath)
        putStrLn ("buildMemoryCeilingPath: " <> buildCeilingPath)
    InternalMaterializeMetalEnginesCommand -> do
      paths <- discoverPaths
      ensureRepoLayout paths
      materializeMetalEngines paths
      mapM_ (putStrLn . ("metalEngineArtifact: " <>) . Text.unpack) metalEngineArtifactAdapterIds
    InternalMaterializeLinuxNativeEnginesCommand -> do
      paths <- discoverPaths
      ensureRepoLayout paths
      materializeLinuxNativeEngines paths
      mapM_ (putStrLn . ("linuxNativeEngineArtifact: " <>) . Text.unpack) linuxNativeEngineArtifactAdapterIds
    InternalDemoConfigLoadCommand demoConfigPath -> do
      demoConfig <- decodeDemoConfigFile demoConfigPath
      putStr (renderModelListing demoConfig)
    InternalDemoConfigValidateCommand demoConfigPath ->
      void (requireCompiledRuntimePlanFile demoConfigPath)
    InternalDhallSchemaCommand schema ->
      case renderDhallSchema schema of
        Left err -> ioError (userError err)
        Right schemaText -> putStr (Text.unpack schemaText)
    InternalGeneratePursContractsCommand outputDir -> do
      runtimeMode <- resolveRuntimeMode Nothing
      writeGeneratedPursContracts runtimeMode outputDir
    InternalPulsarRoundTripCommand demoConfigPath modelIdValue inputTextValue ->
      runInternalPulsarRoundTrip demoConfigPath modelIdValue inputTextValue
    InternalPlaywrightPrepareEngineCommand modelIdValue ->
      runPlaywrightPrepareEngine (Text.pack modelIdValue)

validateCommandExecutionContext :: Command -> IO (Maybe RuntimeMode)
validateCommandExecutionContext command = do
  paths <- discoverPaths
  maybeRuntimeMode <- runtimeModeForCommand command
  maybe (pure ()) (ensureSupportedRuntimeModeForExecutionContext paths) maybeRuntimeMode
  pure maybeRuntimeMode
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
        TestIntegrationCommand -> testRuntimeMode
        TestE2ECommand -> testRuntimeMode
        TestAllCommand -> testRuntimeMode
        InternalMaterializeSubstrateCommand runtimeMode _ _ -> pure (Just runtimeMode)
        InternalGeneratePursContractsCommand _ -> activeRuntimeMode
        _ -> pure Nothing
    activeRuntimeMode = Just <$> ensureActiveSubstrateFile
    testRuntimeMode = do
      paths <- discoverPaths
      let testConfig = testConfigPath paths
      testConfigExists <- doesFileExist testConfig
      if testConfigExists
        then Just . configRuntimeMode <$> decodeDemoConfigFile testConfig
        else activeRuntimeMode

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

runLint :: Maybe RuntimeMode -> IO ()
runLint maybeRuntimeMode =
  withToolchainAuthority $ \authority -> do
    runToolchainCommand authority maybeRuntimeMode (ToolchainTest HaskellStyleSuite)
    runFilesLint
    runChartLint
    runProtoLint
    runDocsLint
    runPythonQualityIfPresent maybeRuntimeMode
    runToolchainCommand authority maybeRuntimeMode ToolchainBuildAll

-- | Sprint 6.43 — run a cluster-owned validation step under an evidence-gated
-- seizure of the single cluster slot. 'seizeHarnessClusterSlot' reads the
-- persisted owner and fails closed loud on an 'OperatorOwned' cluster (never
-- destroying it because release is installed only after successful seizure),
-- tearing down only a 'HarnessOwned' or absent one. Successful seizure and
-- cleanup installation share one masked acquisition boundary. The suite then
-- brings up its own 'HarnessOwned' cluster. Cleanup repeats the locked owner
-- check, so an operator that wins the slot after seizure is never torn down by
-- harness cleanup.
runClusterOwnedValidation :: Maybe RuntimeMode -> IO a -> IO a
runClusterOwnedValidation maybeRuntimeMode action =
  bracketPreservingPrimary
    (seizeHarnessClusterSlot maybeRuntimeMode)
    (const (releaseHarnessClusterSlot maybeRuntimeMode))
    (const action)

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
  testDemoConfig <- decodeDemoConfigFile testConfig
  hadExistingRuntimeConfig <- doesFileExist runtimeConfig
  mask $ \restore -> do
    ( do
        beginHarnessConfigTransaction paths hadExistingRuntimeConfig $ do
          when hadExistingRuntimeConfig (renameFile runtimeConfig backupConfig)
          restore $ do
            _ <-
              materializeGeneratedDemoConfigFile
                paths
                (configRuntimeMode testDemoConfig)
                (demoUiEnabled testDemoConfig)
            pure ()
        restore action
      )
      `finallyPreservingPrimary` completeHarnessConfigTransaction
        paths
        (restoreRuntimeConfig runtimeConfig backupConfig hadExistingRuntimeConfig)

-- | Restore the pre-run @./infernix.dhall@ after a harness run: remove the
-- harness-generated file (and any per-variant rewrite), then move the backup
-- back into place when one was taken.
restoreRuntimeConfig :: FilePath -> FilePath -> Bool -> IO ()
restoreRuntimeConfig runtimeConfig backupConfig hadExistingRuntimeConfig = do
  runtimePresent <- doesFileExist runtimeConfig
  backupPresent <- doesFileExist backupConfig
  case runtimeConfigRestorePlan hadExistingRuntimeConfig backupPresent of
    Right RestoreOperatorRuntimeConfig -> do
      when runtimePresent (removeFile runtimeConfig)
      renameFile backupConfig runtimeConfig
    Right RemoveHarnessRuntimeConfig ->
      when runtimePresent (removeFile runtimeConfig)
    Left refusal -> ioError (userError refusal)

data RuntimeConfigRestorePlan
  = RestoreOperatorRuntimeConfig
  | RemoveHarnessRuntimeConfig

-- Pure policy surface for testing the fail-closed presence matrix. The IO
-- mutator remains private and is reachable only from the reservation-gated
-- config transaction.
runtimeConfigRestorePlan :: Bool -> Bool -> Either String RuntimeConfigRestorePlan
runtimeConfigRestorePlan hadExistingRuntimeConfig backupPresent =
  case (hadExistingRuntimeConfig, backupPresent) of
    (True, True) -> Right RestoreOperatorRuntimeConfig
    (True, False) ->
      Left "cannot complete harness config restore: the required operator-config backup is absent"
    (False, False) -> Right RemoveHarnessRuntimeConfig
    (False, True) ->
      Left "cannot complete harness config removal: an unexpected operator-config backup exists"

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
      clusterUpHarness (Just runtimeMode)
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
    `finallyPreservingPrimary` clusterDownHarness (Just runtimeMode)

runInternalPulsarRoundTrip :: FilePath -> String -> String -> IO ()
runInternalPulsarRoundTrip demoConfigPath modelIdValue inputTextValue = do
  paths <- discoverPaths
  compiledPlan <- requireCompiledRuntimePlanFile demoConfigPath
  let requestValue =
        InferenceRequest
          { requestModelId = Text.pack modelIdValue,
            inputText = Text.pack inputTextValue,
            inputObjectRef = Nothing,
            requestUserId = Nothing,
            requestContextId = Nothing
          }
  requestIdValue <- publishInferenceRequest paths compiledPlan requestValue
  maybeResult <- waitForInternalPulsarResult paths compiledPlan requestIdValue
  case maybeResult of
    Nothing ->
      ioError
        ( userError
            ( "timed out waiting for Pulsar result for request "
                <> Text.unpack requestIdValue
            )
        )
    Just resultValue -> printInternalPulsarResult resultValue

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel under the legacy 120-attempt × 0.25 s budget. A published
-- result is the kernel's readiness evidence; a deadline-exhausted wait resolves to
-- @Nothing@ exactly as the previous bare-recursion fall-through did.
waitForInternalPulsarResult ::
  Paths ->
  ExecutionPlan.CompiledRuntimePlan ->
  Text.Text ->
  IO (Maybe InferenceResult)
waitForInternalPulsarResult paths compiledPlan requestIdValue = do
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 120 250000) probe
  pure (Readiness.foldReadiness Just (const Nothing) (const Nothing) outcome)
  where
    probe = do
      maybeResult <- readPublishedInferenceResultMaybe paths compiledPlan requestIdValue
      case maybeResult of
        Just resultValue -> pure (Right resultValue)
        Nothing -> pure (Left (Readiness.Progress 0 1 "inference result not yet published"))

requireCompiledRuntimePlanFile ::
  FilePath ->
  IO ExecutionPlan.CompiledRuntimePlan
requireCompiledRuntimePlanFile demoConfigPath = do
  compiledResult <- decodeCompiledRuntimePlanFile demoConfigPath
  case compiledResult of
    Left errors ->
      ioError
        ( userError
            ( "runtime config did not compile: "
                <> show errors
            )
        )
    Right compiledPlan -> pure compiledPlan

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

-- | Sprint 6.41 (managed-state-transition doctrine): migrated onto the shared
-- 'Readiness' kernel under the legacy 60-attempt × 1 s budget. A routed surface
-- serving the expected publication + demo-config payloads is the kernel's
-- readiness evidence; a deadline-exhausted wait raises the timeout diagnostic.
waitForPlaywrightSurface :: Paths -> String -> Int -> String -> String -> String -> String -> IO ()
waitForPlaywrightSurface paths host edgePort expectedDaemonLocation expectedInferenceExecutorLocation expectedInferenceDispatchMode expectedApiUpstreamMode = do
  outcome <- Readiness.awaitReadiness (Readiness.budgetDeadline 60 1000000) probe
  Readiness.foldReadiness (const (pure ())) onTimedOut onTimedOut outcome
  where
    probe = do
      ready <- surfaceReady
      if ready
        then pure (Right ())
        else pure (Left (Readiness.Progress 0 1 "routed surface not yet serving publication/demo-config"))
    onTimedOut _ =
      ioError
        ( userError
            ( "timed out waiting for routed surface at "
                <> host
                <> ":"
                <> show edgePort
                <> " to serve publication and demo-config traffic"
            )
        )
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
  bracketPreservingPrimary
    ( do
        (_, _, _, processHandle) <-
          createProcess
            (proc infernixExecutable ["service"])
              { cwd = Just (repoRoot paths)
              }
        pure processHandle
    )
    ( \processHandle ->
        runCleanupsPreservingFailures
          [ terminateProcess processHandle,
            void (waitForProcess processHandle)
          ]
    )
    (const action)

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

-- | Phase 6 Sprint 6.46 — enter the region in which a toolchain process may be
-- started.
--
-- The plan is derived from a live measurement of the machine that will run the
-- build rather than from the manifest's recorded facts, because the two can
-- disagree: the manifest records what the machine looked like when @infernix
-- init@ last ran, and on the Linux launcher lane the image bakes an unmeasured
-- manifest while the container it runs in carries its own cgroup maximum.
withToolchainAuthority ::
  (forall s. ToolchainSpawnAuthority s -> IO result) ->
  IO result
withToolchainAuthority action = do
  paths <- discoverCliCommandPaths
  hostConfig <-
    case pathsHostConfig paths of
      Just hostConfig -> pure hostConfig
      Nothing ->
        ioError
          ( userError
              ( "a toolchain process needs the host manifest to measure this "
                  <> "machine's memory; run `infernix init` to stage "
                  <> "./infernix-host.dhall"
              )
          )
  resolvedPlan <- HostMemory.resolveLiveBuildMemoryPlan hostConfig
  plan <-
    case resolvedPlan of
      Right plan -> pure plan
      Left reason ->
        ioError
          ( userError
              ( "refusing to start a toolchain process without a derived memory "
                  <> "ceiling: "
                  <> reason
              )
          )
  BuildMemory.withToolchainSpawnAuthority plan action

-- | Start one toolchain invocation under the region's derived ceiling.
--
-- The invocation comes from the closed 'ToolchainInvocation' vocabulary, so a
-- build assembled from a caller-supplied argument list is not a term. The
-- ceiling is held in force across the spawn and the child's out-of-memory victim
-- rank is raised as soon as its pid exists.
runToolchainCommand ::
  ToolchainSpawnAuthority s ->
  Maybe RuntimeMode ->
  ToolchainInvocation ->
  IO ()
runToolchainCommand authority _maybeRuntimeMode invocation = do
  paths <- discoverCliCommandPaths
  resolvedCommand <- resolveCliHostTool paths HostCabal
  processHandle <-
    BuildMemory.withBoundedToolchainChild authority $ do
      (_, _, _, spawned) <-
        createProcess
          (proc resolvedCommand (toolchainArguments invocation))
            { env = Just (cliSubprocessBaseEnvFor paths),
              cwd = Just (repoRoot paths)
            }
      pure spawned
  maybeChildPid <- getPid processHandle
  for_ maybeChildPid (BuildMemory.applyToolchainChildVictimRank authority)
  exitCode <- waitForProcess processHandle
  case exitCode of
    ExitSuccess -> pure ()
    _ -> exitWith exitCode
  where
    toolchainArguments = BuildMemory.toolchainInvocationArguments

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
    "python3.11" -> Just HostPython311
    "llama-cli" -> Just HostLlamaCli
    "whisper-cli" -> Just HostWhisperCli
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

-- | Capture a closed host tool's stdout under a required total deadline.
--
-- The sole caller is 'loadTextUrl', which fetches a demo-UI page with @curl@.
-- @curl@ against an unreachable-but-accepting endpoint can block indefinitely,
-- so the capture carries the same 120 s bound the generated host manifest
-- gives every closed 'Infernix.Cluster.Command.CurlProbeOperation'. The caller
-- already classifies an @IOError@ as "page unavailable", so an expired fetch
-- is a named observation rather than a hang.
captureCliHostTool :: Paths -> HostTool -> [String] -> IO String
captureCliHostTool paths tool args = do
  command <- resolveCliHostTool paths tool
  captureOutcome <-
    timeout
      cliHostToolCaptureDeadlineMicros
      ( readCreateProcessWithExitCode
          (proc command args)
            { env = Just (cliSubprocessBaseEnvFor paths)
            }
          ""
      )
  classifyCliHostToolCapture tool captureOutcome

cliHostToolCaptureDeadlineMicros :: Int
cliHostToolCaptureDeadlineMicros = 120 * 1000 * 1000

classifyCliHostToolCapture ::
  HostTool ->
  Maybe (ExitCode, String, String) ->
  IO String
classifyCliHostToolCapture tool captureOutcome =
  case captureOutcome of
    Just (ExitSuccess, stdoutOutput, _) -> pure stdoutOutput
    Just (_, _, stderrOutput) -> ioError (userError stderrOutput)
    Nothing ->
      ioError
        ( userError
            ( "host tool `"
                <> Text.unpack (HostTools.hostToolName tool)
                <> "` capture exceeded its required "
                <> show (cliHostToolCaptureDeadlineMicros `div` 1000000)
                <> "s deadline"
            )
        )

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
          HostPython311,
          HostLlamaCli,
          HostWhisperCli,
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
