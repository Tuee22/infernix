{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}

module Infernix.CLI
  ( main,
    writeGeneratedPursContracts,
    RuntimeConfigRestorePlan,
    runtimeConfigRestorePlan,
    DarwinBuildMemoryProcessGroupFixture (..),
    DarwinBuildMemorySamplingState (..),
    DarwinBuildMemoryTerminalSettlementState (..),
    classifyDarwinBuildMemorySamplingObservation,
    classifyDarwinBuildMemoryTerminalSettlement,
    commandRequiresConfiguredStartup,
    runDarwinBuildMemoryProcessGroupFixtureForTest,
    runDarwinBuildMemoryTerminalSettlementFixtureForTest,
  )
where

import Control.Applicative ((<|>))
import Control.Concurrent (ThreadId, forkFinally, killThread)
import Control.Concurrent.MVar (MVar, newEmptyMVar, putMVar, readMVar, tryReadMVar)
import Control.Exception (IOException, SomeException, catch, displayException, evaluate, mask, throwIO, try)
import Control.Monad (unless, void, when)
import Data.Aeson (Value (..), eitherDecode, encode, object, (.=))
import Data.Aeson.Key qualified as Key
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.ByteString.Lazy.Char8 qualified as LazyChar8
import Data.IORef (atomicModifyIORef', newIORef, readIORef, writeIORef)
import Data.List (intercalate, isInfixOf, isPrefixOf)
import Data.List qualified as List
import Data.Text qualified as Text
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import GHC.IO.Encoding (setLocaleEncoding, utf8)
import Infernix.BuildMemory
  ( DarwinAppleMaterializerTest
      ( DarwinInstalledPythonSourceIsolation,
        DarwinProductionAudiverisCancellation
      ),
    ToolchainInvocation
      ( ToolchainBuildAll,
        ToolchainCabalFormat,
        ToolchainDarwinAppleMaterializerTest,
        ToolchainTest
      ),
    ToolchainSpawnAuthority,
    ToolchainTestSuite
      ( AppleMaterializerSuite,
        ArtifactTransactionSuite,
        CappedEngineObserverSuite,
        CompileFailSuite,
        ExecutionPlanInternalSuite,
        HaskellStyleSuite,
        IntegrationSuite,
        UnitSuite
      ),
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
import Infernix.DescriptorSpace (establishBoundedDescriptorSpace, requireBoundedDescriptorSpace)
import Infernix.DhallSchema (renderDhallSchema)
import Infernix.Engines.AppleSilicon (materializeMetalEngines, metalEngineArtifactAdapterIds)
import Infernix.Engines.LinuxNative (linuxNativeEngineArtifactAdapterIds, materializeLinuxNativeEngines)
import Infernix.Error
  ( InfernixError (EdgePortNotPublished),
    bracketPreservingPrimary,
    finallyPreservingPrimary,
    onExceptionPreservingPrimary,
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
import Infernix.Lint.Plan (runPlanLint)
import Infernix.Lint.Proto (runProtoLint)
import Infernix.Models (expectedDaemonLocationForRuntime, expectedInferenceDispatchModeForRuntime, expectedInferenceExecutorLocationForRuntime)
import Infernix.ProjectInit (runProjectInit, runTestInit)
import Infernix.Python
  ( ensurePoetryExecutable,
    ensurePoetryProjectReady,
    ensurePreparedPythonEngineEnvironments,
    pythonAdaptersPresent,
    pythonProjectDirectory,
  )
import Infernix.Runtime (evictCache, listCacheManifests, rebuildCache)
import Infernix.Runtime.CappedEngine.FixedObserver qualified as FixedObserver
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
    getTemporaryDirectory,
    removeFile,
    removePathForcibly,
    renameFile,
    setPermissions,
  )
import System.Environment (getArgs, getExecutablePath)
import System.Exit (ExitCode (..), exitFailure, exitWith)
import System.FilePath (takeDirectory, takeFileName, (</>))
import System.IO (Handle, hClose, hFlush, hIsClosed, stderr, stdout)
import System.IO.Error (isDoesNotExistError, isPermissionError)
import System.Info (os)
import System.Posix.Process (getProcessGroupIDOf)
import System.Posix.Signals (sigCONT, sigKILL, signalProcessGroup)
import System.Posix.Temp (mkdtemp)
import System.Posix.Types (CPid)
import System.Process
  ( CreateProcess (close_fds, create_group, cwd, env, std_err, std_in, std_out),
    ProcessHandle,
    StdStream (CreatePipe, Inherit),
    createProcess,
    getPid,
    proc,
    readCreateProcessWithExitCode,
    terminateProcess,
    waitForProcess,
  )
import System.Timeout (timeout)

main :: IO ()
main = do
  -- Before the internal self-exec dispatch, because those images spawn too,
  -- and before anything opens a descriptor, which is what makes the bound
  -- sound rather than merely cheap. See "Infernix.DescriptorSpace".
  _ <- establishBoundedDescriptorSpace
  dispatchInternalSubprocessMode
  setLocaleEncoding utf8
  args <- getArgs
  case (args == [darwinInstalledCliIsolationProofArgument], parseCommand args) of
    (True, _) -> pure ()
    (False, Left _) -> do
      putStrLn helpText
      exitFailure
    (False, Right command)
      | commandRequiresConfiguredStartup command -> do
          syncBuildRootExecutable
          reconcileInterruptedHarnessState
          resolvedRuntimeMode <- validateCommandExecutionContext command
          ensureAppleHostPrerequisites resolvedRuntimeMode command
          dispatch command
      | otherwise -> dispatch command

-- | Commands that must remain reachable before, or while replacing, a host
-- manifest do not enter any path that decodes that manifest. In particular,
-- @init --force@ is the schema-migration boundary: requiring the old schema to
-- decode before the new schema can be written would make upgrades impossible.
commandRequiresConfiguredStartup :: Command -> Bool
commandRequiresConfiguredStartup command =
  case command of
    ShowRootHelp -> False
    ShowTopicHelp _ -> False
    InitCommand {} -> False
    TestInitCommand {} -> False
    _ -> True

dispatchInternalSubprocessMode :: IO ()
dispatchInternalSubprocessMode =
  Subprocess.dispatchInternalSubprocessMode

dispatch :: Command -> IO ()
dispatch command =
  case command of
    ShowRootHelp -> putStrLn helpText
    ShowTopicHelp topic -> putStrLn (topicHelpText topic)
    InitCommand maybeRuntimeMode maybeDemoUi force ifMissing -> do
      paths <- discoverPathsWithHostManifest Nothing
      withRuntimeConfigWriteAccessAt
        paths
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
    LintPlanCommand -> runPlanLint
    TestLintCommand -> runLint Nothing
    TestUnitCommand -> do
      ensureWebDependencies
      ensurePythonAdapterDependencies Nothing
      runMachineIndependentHaskellTests Nothing
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
      runMachineIndependentHaskellTests Nothing
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
        -- Phase 1 Sprint 1.23: reload the manifest-backed paths that the
        -- command has just published, then prepare the closed per-engine
        -- framework plan. Linux GPU has no base-image plan; its engine images
        -- remain engine-specific. No inference request can enter this producer.
        preparedPaths <- discoverPaths
        ensurePreparedPythonEngineEnvironments preparedPaths runtimeMode
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
    InternalValidateDarwinBuildMemoryCommand ->
      runDarwinBuildMemoryValidation
    InternalValidateDarwinAudiverisCancellationCommand ->
      runDarwinAppleMaterializerTest DarwinProductionAudiverisCancellation
    InternalValidateDarwinInstalledPythonSourceIsolationCommand ->
      runDarwinAppleMaterializerTest DarwinInstalledPythonSourceIsolation
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
    runToolchainCommand authority maybeRuntimeMode ToolchainCabalFormat
    runFilesLint
    runChartLint
    runProtoLint
    runDocsLint
    -- Phase 0 Sprint 0.24: the development-plan standards are enforced by the
    -- aggregate gate rather than by a maintenance pass someone remembers to
    -- perform. The scans stayed outside `runLint` only while they measured the
    -- Section C and Section D backlog that preceded them; with the corpus at
    -- zero, leaving them out is what would let the backlog silently return.
    runPlanLint
    runPythonQualityIfPresent maybeRuntimeMode
    runToolchainCommand authority maybeRuntimeMode ToolchainBuildAll

-- | The complete machine-independent Haskell gate set. Keeping every suite in
-- the closed 'ToolchainTestSuite' vocabulary means no validation instruction
-- needs a bare host Cabal command, and the compile-fail suite's serialized
-- nested account remains beneath the same outer authority.
runMachineIndependentHaskellTests :: Maybe RuntimeMode -> IO ()
runMachineIndependentHaskellTests maybeRuntimeMode =
  withToolchainAuthority $ \authority ->
    mapM_
      (runToolchainCommand authority maybeRuntimeMode . ToolchainTest)
      [ CompileFailSuite,
        ArtifactTransactionSuite,
        AppleMaterializerSuite,
        CappedEngineObserverSuite,
        ExecutionPlanInternalSuite,
        UnitSuite
      ]

runDarwinAppleMaterializerTest :: DarwinAppleMaterializerTest -> IO ()
runDarwinAppleMaterializerTest darwinTest
  | os /= "darwin" =
      ioError
        ( userError
            "the closed Darwin Apple materializer cohort gates are available only on Darwin"
        )
  | otherwise =
      withToolchainAuthority $ \authority ->
        runToolchainCommand
          authority
          Nothing
          (ToolchainDarwinAppleMaterializerTest darwinTest)

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

-- | A normal Cabal child whose fresh process group is owned until the command
-- has completed or exceptional cleanup has killed and reaped the group.
data OwnedToolchainProcess = OwnedToolchainProcess
  { ownedToolchainProcessHandle :: !ProcessHandle,
    ownedToolchainProcessGroup :: !CPid
  }

-- | The Darwin evidence command owns the complete process group until its
-- relayed output streams have closed, the fixed observer proves no descendant
-- remains, the leader is reaped, and the numeric group is absent. Retaining the
-- unreaped leader across the descendant proof prevents PID/PGID reuse from
-- turning a cleanup observation into evidence about a different process.
data DarwinBuildMemoryProcess = DarwinBuildMemoryProcess
  { darwinBuildMemoryProcessHandle :: !ProcessHandle,
    darwinBuildMemoryProcessGroup :: !CPid,
    darwinBuildMemoryStdoutHandle :: !Handle,
    darwinBuildMemoryStderrHandle :: !Handle,
    darwinBuildMemoryStdoutThread :: !ThreadId,
    darwinBuildMemoryStderrThread :: !ThreadId,
    darwinBuildMemoryStdoutResult :: !(MVar (Either SomeException ())),
    darwinBuildMemoryStderrResult :: !(MVar (Either SomeException ()))
  }

data DarwinBuildMemoryProcessSpec = DarwinBuildMemoryProcessSpec
  { darwinBuildMemorySpecExecutable :: !FilePath,
    darwinBuildMemorySpecArguments :: ![String],
    darwinBuildMemorySpecWorkingDirectory :: !FilePath,
    darwinBuildMemorySpecEnvironment :: ![(String, String)],
    darwinBuildMemorySpecLabel :: !String
  }

-- | Closed test-only process behaviors for the command's normal and
-- exceptional ownership boundaries. Neither constructor carries an executable,
-- argument, environment, or working-directory escape hatch.
data DarwinBuildMemoryProcessGroupFixture
  = DarwinBuildMemoryNormalCleanupFixture
  | DarwinBuildMemoryExceptionalCleanupFixture
  deriving (Eq, Show)

-- | Pure sampling decision. Relay closure is recorded only to make the
-- terminal-candidate diagnostic complete; it cannot terminate sampling while
-- the fixed footprint observer still sees a live process-group aggregate.
data DarwinBuildMemorySamplingState
  = DarwinBuildMemorySamplingObserved !Word64
  | DarwinBuildMemorySamplingNeedsTerminalSettlement !Bool !Text.Text
  deriving (Eq, Show)

classifyDarwinBuildMemorySamplingObservation ::
  Bool ->
  Either Text.Text Word64 ->
  DarwinBuildMemorySamplingState
classifyDarwinBuildMemorySamplingObservation streamsClosed observedFootprint =
  case observedFootprint of
    Right physicalFootprintBytes ->
      DarwinBuildMemorySamplingObserved physicalFootprintBytes
    Left reason ->
      DarwinBuildMemorySamplingNeedsTerminalSettlement streamsClosed reason

-- | Pure state of the bounded terminal settlement entered only after a live
-- footprint observation fails. A vanished group with relay scheduling lag is
-- pending, not a fabricated observer failure; settlement requires both facts.
data DarwinBuildMemoryTerminalSettlementState
  = DarwinBuildMemoryTerminalSettled
  | DarwinBuildMemoryTerminalPending !Int !Text.Text
  | DarwinBuildMemoryTerminalLiveGroup
  deriving (Eq, Show)

classifyDarwinBuildMemoryTerminalSettlement ::
  Bool ->
  Either Text.Text Bool ->
  Either Text.Text DarwinBuildMemoryTerminalSettlementState
classifyDarwinBuildMemoryTerminalSettlement streamsClosed observedGroupAbsent = do
  groupAbsent <- observedGroupAbsent
  if not groupAbsent
    then Right DarwinBuildMemoryTerminalLiveGroup
    else
      if streamsClosed
        then Right DarwinBuildMemoryTerminalSettled
        else
          Right
            ( DarwinBuildMemoryTerminalPending
                1
                "output relays open; live process group absent"
            )

-- | Closed, opt-in Phase 1 Darwin calibration surface. Nothing in an ordinary
-- lint, test, init, or cluster command enters this path.
runDarwinBuildMemoryValidation :: IO ()
runDarwinBuildMemoryValidation = do
  unless (os == "darwin") $
    ioError
      ( userError
          "`infernix internal validate-darwin-build-memory` is available only on Darwin"
      )
  paths <- discoverCliCommandPaths
  hostConfig <-
    case pathsHostConfig paths of
      Just configured -> pure configured
      Nothing ->
        ioError
          ( userError
              "Darwin build-memory validation requires the generated host manifest; run `infernix init`"
          )
  observedFacts <-
    HostMemory.observeHostMemoryFacts hostConfig
      >>= either (ioError . userError) pure
  plan <-
    either
      (ioError . userError)
      pure
      ( HostMemory.buildMemoryPlanForHost
          hostConfig {HostConfig.hostMemory = observedFacts}
      )
  let physicalMib =
        toInteger (HostConfig.hostPhysicalMemoryMib observedFacts)
      effectiveMib =
        toInteger (HostConfig.hostEffectiveMemoryMib observedFacts)
      activeColimaPledgeMib = physicalMib - effectiveMib
  unless
    ( physicalMib > 0
        && effectiveMib > 0
        && effectiveMib <= physicalMib
    )
    ( ioError
        ( userError
            "Darwin build-memory validation observed inconsistent physical/effective host memory before spawn"
        )
    )
  BuildMemory.withToolchainSpawnAuthority (repoRoot paths) plan $ \authority -> do
    darwinAuthority <-
      either
        (ioError . userError)
        pure
        (BuildMemory.requireDarwinBuildMemoryValidationAuthority authority)
    withDarwinBuildMemoryScratchRoot $ \scratchRoot -> do
      createDirectoryIfMissing True (scratchRoot </> "bin")
      (buildEvidence, buildExitCode) <-
        runDarwinBuildMemoryInvocation
          paths
          darwinAuthority
          scratchRoot
          BuildMemory.DarwinBuildAllWithTests
      (invocationEvidence, installedCliIsolation, finalExitCode) <-
        case buildExitCode of
          ExitSuccess -> do
            (installEvidence, installExitCode) <-
              runDarwinBuildMemoryInvocation
                paths
                darwinAuthority
                scratchRoot
                BuildMemory.DarwinInstallAllExecutables
            case installExitCode of
              ExitSuccess -> do
                isolationExitCode <-
                  runDarwinInstalledCliIsolationProof
                    paths
                    darwinAuthority
                    scratchRoot
                isolationEvidence <-
                  either
                    (ioError . userError)
                    pure
                    ( BuildMemory.mkDarwinInstalledCliIsolationEvidence
                        (exitCodeStatus isolationExitCode)
                    )
                pure
                  ( [buildEvidence, installEvidence],
                    Just isolationEvidence,
                    isolationExitCode
                  )
              _ -> pure ([buildEvidence, installEvidence], Nothing, installExitCode)
          _ -> pure ([buildEvidence], Nothing, buildExitCode)
      evidence <-
        either
          (ioError . userError)
          pure
          ( BuildMemory.mkDarwinBuildMemoryEvidence
              physicalMib
              effectiveMib
              activeColimaPledgeMib
              darwinAuthority
              BuildMemory.darwinBuildMemorySampleIntervalMicros
              invocationEvidence
              installedCliIsolation
          )
      putStr (BuildMemory.renderDarwinBuildMemoryEvidence evidence)
      case finalExitCode of
        ExitSuccess -> pure ()
        failure -> exitWith failure

withDarwinBuildMemoryScratchRoot :: (FilePath -> IO result) -> IO result
withDarwinBuildMemoryScratchRoot action = do
  temporaryRoot <- getTemporaryDirectory
  bracketPreservingPrimary
    (mkdtemp (temporaryRoot </> "infernix-darwin-build-memory.XXXXXX"))
    removePathForcibly
    action

runDarwinBuildMemoryProcessGroupFixtureForTest ::
  DarwinBuildMemoryProcessGroupFixture ->
  IO ()
runDarwinBuildMemoryProcessGroupFixtureForTest fixture
  | os /= "darwin" =
      ioError
        ( userError
            "Darwin build-memory process-group fixtures are available only on Darwin"
        )
  | otherwise = do
      executable <- getExecutablePath
      mask $ \restore -> do
        spawned <-
          spawnDarwinBuildMemoryProcessSpec
            DarwinBuildMemoryProcessSpec
              { darwinBuildMemorySpecExecutable = executable,
                darwinBuildMemorySpecArguments =
                  [darwinBuildMemoryCleanupFixtureArgument fixture],
                darwinBuildMemorySpecWorkingDirectory = "/tmp",
                darwinBuildMemorySpecEnvironment =
                  [ ("LANG", "C"),
                    ("LC_ALL", "C"),
                    ("PATH", "/usr/bin:/bin"),
                    ("TMPDIR", "/tmp")
                  ],
                darwinBuildMemorySpecLabel =
                  "closed Darwin build-memory cleanup fixture"
              }
        case fixture of
          DarwinBuildMemoryNormalCleanupFixture -> do
            observed <-
              onExceptionPreservingPrimary
                ( restore $ do
                    awaitDarwinBuildMemoryStreamClosure spawned
                    sampleDarwinBuildMemoryProcess spawned
                )
                (cleanupDarwinBuildMemoryProcess spawned)
            when (observed == BuildMemory.emptyDarwinBuildMemorySamples) $
              ioError
                ( userError
                    "Darwin build-memory live-after-relay-closure fixture recorded no process-group sample"
                )
            exitCode <- completeDarwinBuildMemoryProcess spawned
            unless (exitCode == ExitSuccess) $
              ioError
                ( userError
                    "normal Darwin build-memory cleanup fixture exited nonzero"
                )
          DarwinBuildMemoryExceptionalCleanupFixture -> do
            injected <-
              try @SomeException
                ( onExceptionPreservingPrimary
                    ( restore
                        ( ioError
                            ( userError
                                darwinBuildMemoryInjectedCleanupFailure
                            )
                        )
                    )
                    (cleanupDarwinBuildMemoryProcess spawned)
                )
            case injected of
              Left failure
                | darwinBuildMemoryInjectedCleanupFailure
                    `isInfixOf` displayException failure ->
                    pure ()
              Left failure -> throwIO failure
              Right () ->
                ioError
                  ( userError
                      "exceptional Darwin build-memory cleanup fixture did not inject its failure"
                  )

-- | Deterministic regression for the terminal race: the process group has
-- already vanished, while relay completion becomes observable only after two
-- readiness polls. No executable, arguments, or observer command are exposed.
runDarwinBuildMemoryTerminalSettlementFixtureForTest :: IO ()
runDarwinBuildMemoryTerminalSettlementFixtureForTest = do
  relayPolls <- newIORef (0 :: Int)
  awaitDarwinBuildMemoryTerminalSettlementWith
    "injected terminal footprint race"
    ( atomicModifyIORef' relayPolls $ \polls ->
        let next = polls + 1
         in (next, next >= 3)
    )
    (pure (Right True))

awaitDarwinBuildMemoryStreamClosure :: DarwinBuildMemoryProcess -> IO ()
awaitDarwinBuildMemoryStreamClosure spawned = do
  outcome <-
    Readiness.awaitReadiness darwinBuildMemoryCleanupDeadline $ do
      finished <- darwinBuildMemoryStreamsFinished spawned
      pure $
        if finished
          then Right ()
          else
            Left
              ( Readiness.Progress
                  0
                  1
                  "Darwin build-memory output streams remain open"
              )
  Readiness.foldReadiness
    (const (pure ()))
    onDeadline
    onDeadline
    outcome
  where
    onDeadline _ =
      ioError
        ( userError
            "Darwin build-memory cleanup fixture streams did not close before their deadline"
        )

darwinBuildMemoryCleanupFixtureArgument ::
  DarwinBuildMemoryProcessGroupFixture ->
  String
darwinBuildMemoryCleanupFixtureArgument fixture =
  case fixture of
    DarwinBuildMemoryNormalCleanupFixture ->
      "__infernix_unit_darwin_build_memory_normal_cleanup_fixture"
    DarwinBuildMemoryExceptionalCleanupFixture ->
      "__infernix_unit_darwin_build_memory_exceptional_cleanup_fixture"

darwinBuildMemoryInjectedCleanupFailure :: String
darwinBuildMemoryInjectedCleanupFailure =
  "injected Darwin build-memory command failure"

runDarwinBuildMemoryInvocation ::
  Paths ->
  BuildMemory.DarwinBuildMemoryValidationAuthority s ->
  FilePath ->
  BuildMemory.DarwinBuildMemoryInvocation ->
  IO (BuildMemory.DarwinBuildMemoryInvocationEvidence, ExitCode)
runDarwinBuildMemoryInvocation
  paths
  authority
  scratchRoot
  invocation = do
    startedAt <- getMonotonicTimeNSec
    (samples, exitCode) <-
      BuildMemory.withDarwinBuildMemoryValidationChild authority $
        mask $ \restore -> do
          spawned <-
            spawnDarwinBuildMemoryProcess
              paths
              authority
              scratchRoot
              invocation
          observed <-
            onExceptionPreservingPrimary
              (restore (sampleDarwinBuildMemoryProcess spawned))
              (cleanupDarwinBuildMemoryProcess spawned)
          completed <- completeDarwinBuildMemoryProcess spawned
          pure (observed, completed)
    finishedAt <- getMonotonicTimeNSec
    invocationEvidence <-
      either
        (ioError . userError)
        pure
        ( BuildMemory.mkDarwinBuildMemoryInvocationEvidence
            invocation
            (exitCodeStatus exitCode)
            ((finishedAt - startedAt) `div` 1000)
            samples
        )
    pure (invocationEvidence, exitCode)

-- | Prove that the freshly installed runtime CLI cannot accidentally consume
-- the build-only @GHCRTS@ cap. The fixed invalid value makes any RTS image that
-- still admits inherited options fail before @main@; the shipped executable is
-- linked with @-rtsopts=ignoreAll@ and must reach its fixed package-internal
-- isolation sentinel without performing ordinary CLI artifact synchronization.
-- This process gets the same owned-group, explicit cwd/environment, descriptor
-- precheck, safe leader-reap transition, and exceptional cleanup as the
-- sampled Cabal children, but is deliberately not included in their
-- physical-footprint metric.
runDarwinInstalledCliIsolationProof ::
  Paths ->
  BuildMemory.DarwinBuildMemoryValidationAuthority s ->
  FilePath ->
  IO ExitCode
runDarwinInstalledCliIsolationProof paths authority scratchRoot =
  BuildMemory.withDarwinBuildMemoryValidationChild authority $
    mask $ \restore -> do
      spawned <-
        spawnDarwinBuildMemoryProcessSpec
          DarwinBuildMemoryProcessSpec
            { darwinBuildMemorySpecExecutable = scratchRoot </> "bin" </> "infernix",
              darwinBuildMemorySpecArguments = [darwinInstalledCliIsolationProofArgument],
              darwinBuildMemorySpecWorkingDirectory = repoRoot paths,
              darwinBuildMemorySpecEnvironment =
                mergeEnvironment
                  [("GHCRTS", darwinInstalledCliAdversarialGhcrts)]
                  (cliSubprocessBaseEnvFor paths),
              darwinBuildMemorySpecLabel =
                "freshly installed runtime CLI GHCRTS-isolation proof"
            }
      onExceptionPreservingPrimary
        (restore (awaitDarwinBuildMemoryStreamClosure spawned))
        (cleanupDarwinBuildMemoryProcess spawned)
      completeDarwinBuildMemoryProcess spawned

darwinInstalledCliAdversarialGhcrts :: String
darwinInstalledCliAdversarialGhcrts =
  "--infernix-build-only-ghcrts-must-be-ignored"

-- A fixed package-internal self-exec sentinel, not a caller-supplied command
-- surface. It returns only after the shipped runtime image has entered Haskell
-- @main@ under the adversarial inherited GHCRTS value. Handling it before
-- 'syncBuildRootExecutable' keeps the private scratch install proof read-only
-- with respect to the repository build root.
darwinInstalledCliIsolationProofArgument :: String
darwinInstalledCliIsolationProofArgument =
  "__infernix_internal_darwin_runtime_ghcrts_isolation_v1"

spawnDarwinBuildMemoryProcess ::
  Paths ->
  BuildMemory.DarwinBuildMemoryValidationAuthority s ->
  FilePath ->
  BuildMemory.DarwinBuildMemoryInvocation ->
  IO DarwinBuildMemoryProcess
spawnDarwinBuildMemoryProcess paths authority scratchRoot invocation = do
  cabalExecutable <- resolveCliHostTool paths HostCabal
  arguments <-
    either
      (ioError . userError)
      pure
      ( BuildMemory.darwinBuildMemoryInvocationArguments
          authority
          invocation
          scratchRoot
      )
  spawnDarwinBuildMemoryProcessSpec
    DarwinBuildMemoryProcessSpec
      { darwinBuildMemorySpecExecutable = cabalExecutable,
        darwinBuildMemorySpecArguments = arguments,
        darwinBuildMemorySpecWorkingDirectory = repoRoot paths,
        darwinBuildMemorySpecEnvironment = cliSubprocessBaseEnvFor paths,
        darwinBuildMemorySpecLabel =
          BuildMemory.darwinBuildMemoryInvocationLabel invocation
      }

spawnDarwinBuildMemoryProcessSpec ::
  DarwinBuildMemoryProcessSpec ->
  IO DarwinBuildMemoryProcess
spawnDarwinBuildMemoryProcessSpec spec = do
  _ <-
    requireBoundedDescriptorSpace
      (darwinBuildMemorySpecLabel spec <> " process-group spawn")
  created <-
    createProcess
      (proc (darwinBuildMemorySpecExecutable spec) (darwinBuildMemorySpecArguments spec))
        { cwd = Just (darwinBuildMemorySpecWorkingDirectory spec),
          env = Just (darwinBuildMemorySpecEnvironment spec),
          std_in = Inherit,
          std_out = CreatePipe,
          std_err = CreatePipe,
          close_fds = True,
          create_group = True
        }
  let (_, maybeOutput, maybeError, processHandle) = created
      inheritedHandles = [maybeOutput, maybeError]
      cleanupBeforeGroup =
        runCleanupsPreservingFailures
          [ ignoreMissingProcess (terminateProcess processHandle),
            void
              ( waitForDarwinBuildMemoryProcess
                  "unidentified Darwin build-memory child"
                  processHandle
              ),
            mapM_ closeHandleIfOpen (foldMap maybeToList inheritedHandles)
          ]
  maybeProcessId <-
    onExceptionPreservingPrimary
      (getPid processHandle)
      cleanupBeforeGroup
  processGroup <-
    case maybeProcessId of
      Just processId -> pure processId
      Nothing ->
        onExceptionPreservingPrimary
          ( ioError
              ( userError
                  "Darwin build-memory child exited before its process-group identity was observed"
              )
          )
          cleanupBeforeGroup
  let cleanupGrouped =
        cleanupDarwinBuildMemoryProcessParts processHandle processGroup
  onExceptionPreservingPrimary
    (validateDarwinBuildMemoryProcessGroup processGroup)
    (cleanupGrouped (foldMap maybeToList inheritedHandles) [])
  (outputHandle, errorHandle) <-
    case (maybeOutput, maybeError) of
      (Just output, Just err) -> pure (output, err)
      _ ->
        onExceptionPreservingPrimary
          ( ioError
              ( userError
                  "Darwin build-memory child did not expose both output pipes"
              )
          )
          (cleanupGrouped (foldMap maybeToList inheritedHandles) [])
  stdoutResult <- newEmptyMVar
  stderrResult <- newEmptyMVar
  stdoutThread <-
    onExceptionPreservingPrimary
      (forkFinally (relayDarwinBuildMemoryOutput outputHandle stdout) (putMVar stdoutResult))
      (cleanupGrouped [outputHandle, errorHandle] [])
  stderrThread <-
    onExceptionPreservingPrimary
      (forkFinally (relayDarwinBuildMemoryOutput errorHandle stderr) (putMVar stderrResult))
      (cleanupGrouped [outputHandle, errorHandle] [stdoutThread])
  pure
    DarwinBuildMemoryProcess
      { darwinBuildMemoryProcessHandle = processHandle,
        darwinBuildMemoryProcessGroup = processGroup,
        darwinBuildMemoryStdoutHandle = outputHandle,
        darwinBuildMemoryStderrHandle = errorHandle,
        darwinBuildMemoryStdoutThread = stdoutThread,
        darwinBuildMemoryStderrThread = stderrThread,
        darwinBuildMemoryStdoutResult = stdoutResult,
        darwinBuildMemoryStderrResult = stderrResult
      }

validateDarwinBuildMemoryProcessGroup :: CPid -> IO ()
validateDarwinBuildMemoryProcessGroup processGroup = do
  observedGroup <- getProcessGroupIDOf processGroup
  unless (observedGroup == processGroup) $
    ioError
      ( userError
          "Darwin build-memory child was not isolated in its requested fresh process group"
      )

relayDarwinBuildMemoryOutput :: Handle -> Handle -> IO ()
relayDarwinBuildMemoryOutput source destination =
  finallyPreservingPrimary loop (closeHandleIfOpen source)
  where
    loop = do
      chunk <- ByteString.hGetSome source darwinBuildMemoryRelayChunkBytes
      unless (ByteString.null chunk) $ do
        ByteString.hPut destination chunk
        hFlush destination
        loop

sampleDarwinBuildMemoryProcess ::
  DarwinBuildMemoryProcess ->
  IO BuildMemory.DarwinBuildMemorySamples
sampleDarwinBuildMemoryProcess spawned = do
  samplesRef <- newIORef (BuildMemory.emptyDarwinBuildMemorySamples, 0)
  outcome <-
    Readiness.awaitReadiness darwinBuildMemorySamplingDeadline (probe samplesRef)
  Readiness.foldReadiness
    pure
    onDeadline
    onDeadline
    outcome
  where
    probe samplesRef = do
      streamsFinished <- darwinBuildMemoryStreamsFinished spawned
      observed <-
        FixedObserver.processGroupPhysicalFootprintBytes
          (darwinBuildMemoryProcessGroup spawned)
      case classifyDarwinBuildMemorySamplingObservation streamsFinished observed of
        DarwinBuildMemorySamplingNeedsTerminalSettlement _ reason -> do
          awaitDarwinBuildMemoryTerminalSettlementWith
            (Text.unpack reason)
            (darwinBuildMemoryStreamsFinished spawned)
            ( FixedObserver.processGroupHasNoLiveMembers
                (darwinBuildMemoryProcessGroup spawned)
            )
          -- The process crossed its ordinary terminal boundary during the
          -- footprint probe. Relay closure and a fixed complete group snapshot
          -- now prove the terminal state while the unreaped leader still
          -- protects the identity.
          Right . fst <$> readIORef samplesRef
        DarwinBuildMemorySamplingObserved physicalFootprintBytes -> do
          (samples, sampleCount) <- readIORef samplesRef
          nextSamples <-
            either
              (ioError . userError)
              pure
              (BuildMemory.recordDarwinBuildMemorySample physicalFootprintBytes samples)
          let nextCount = sampleCount + 1
          writeIORef samplesRef (nextSamples, nextCount)
          pure
            ( Left
                ( Readiness.Progress
                    nextCount
                    darwinBuildMemoryMaximumSamples
                    "sampled Darwin Cabal process-group aggregate physical footprint"
                )
            )
    onDeadline _ =
      ioError
        ( userError
            "Darwin build-memory sampling exceeded its fixed four-hour/14400-sample ceiling"
        )

awaitDarwinBuildMemoryTerminalSettlementWith ::
  String ->
  IO Bool ->
  IO (Either Text.Text Bool) ->
  IO ()
awaitDarwinBuildMemoryTerminalSettlementWith observerFailure streamsClosedProbe groupAbsentProbe = do
  outcome <-
    Readiness.awaitReadiness darwinBuildMemoryCleanupDeadline probe
  Readiness.foldReadiness
    (const (pure ()))
    onDeadline
    onDeadline
    outcome
  where
    probe = do
      streamsClosed <- streamsClosedProbe
      groupAbsent <- groupAbsentProbe
      case classifyDarwinBuildMemoryTerminalSettlement streamsClosed groupAbsent of
        Left absenceReason ->
          ioError
            ( userError
                ( "Darwin build-memory footprint observer failed and its terminal group observer also failed closed: "
                    <> observerFailure
                    <> "; "
                    <> Text.unpack absenceReason
                )
            )
        Right DarwinBuildMemoryTerminalSettled -> pure (Right ())
        Right DarwinBuildMemoryTerminalLiveGroup ->
          ioError
            ( userError
                ( "Darwin build-memory footprint observer failed while the process group still had a live member; refusing incomplete sampling evidence: "
                    <> observerFailure
                )
            )
        Right (DarwinBuildMemoryTerminalPending observed detail) ->
          pure
            ( Left
                ( Readiness.Progress
                    observed
                    2
                    detail
                )
            )
    onDeadline progress =
      ioError
        ( userError
            ( "live Darwin build-memory observer failed closed while the process did not reach bounded relay/group settlement: "
                <> observerFailure
                <> "; "
                <> Text.unpack (Readiness.progressDetail progress)
            )
        )

darwinBuildMemoryStreamsFinished :: DarwinBuildMemoryProcess -> IO Bool
darwinBuildMemoryStreamsFinished spawned = do
  stdoutResult <- tryReadMVar (darwinBuildMemoryStdoutResult spawned)
  stderrResult <- tryReadMVar (darwinBuildMemoryStderrResult spawned)
  mapM_ requireDarwinBuildMemoryRelay [stdoutResult, stderrResult]
  pure $
    case (stdoutResult, stderrResult) of
      (Just (Right ()), Just (Right ())) -> True
      _ -> False

requireDarwinBuildMemoryRelay :: Maybe (Either SomeException ()) -> IO ()
requireDarwinBuildMemoryRelay maybeResult =
  case maybeResult of
    Just (Left failure) ->
      ioError
        ( userError
            ( "Darwin build-memory output relay failed: "
                <> displayException failure
            )
        )
    _ -> pure ()

completeDarwinBuildMemoryProcess :: DarwinBuildMemoryProcess -> IO ExitCode
completeDarwinBuildMemoryProcess spawned =
  mask $ \restore -> do
    -- Retain the unreaped leader's identity while any live group member could
    -- still require group signaling. Failure in this phase owns that identity
    -- and may safely kill the group before reaping the leader.
    onExceptionPreservingPrimary
      ( restore
          ( awaitDarwinBuildMemoryLiveGroupAbsence
              (darwinBuildMemoryProcessGroup spawned)
          )
      )
      (cleanupDarwinBuildMemoryProcess spawned)
    -- Once the complete observer has proved no live member remains, cross the
    -- reap boundary under the mask. From here on no cleanup may signal the
    -- numeric PGID: after the masked nonblocking reap it can be reused by an
    -- unrelated group. ProcessHandle transition and relay-resource cleanup
    -- remain safe.
    onExceptionPreservingPrimary
      ( do
          exitCode <-
            waitForToolchainProcessLeader
              "normally completed Darwin build-memory Cabal leader"
              (darwinBuildMemoryProcessHandle spawned)
          stdoutResult <- readMVar (darwinBuildMemoryStdoutResult spawned)
          stderrResult <- readMVar (darwinBuildMemoryStderrResult spawned)
          mapM_ (requireDarwinBuildMemoryRelay . Just) [stdoutResult, stderrResult]
          cleanupDarwinBuildMemoryLocalResources spawned
          pure exitCode
      )
      (cleanupDarwinBuildMemoryAfterLiveGroupAbsence spawned)

awaitDarwinBuildMemoryLiveGroupAbsence :: CPid -> IO ()
awaitDarwinBuildMemoryLiveGroupAbsence processGroup = do
  outcome <-
    Readiness.awaitReadiness darwinBuildMemoryCleanupDeadline probe
  Readiness.foldReadiness
    (const (pure ()))
    onDeadline
    onDeadline
    outcome
  where
    probe = do
      observed <- FixedObserver.processGroupHasNoLiveMembers processGroup
      case observed of
        Left reason ->
          ioError
            ( userError
                ( "Darwin build-memory live-group observer failed closed: "
                    <> Text.unpack reason
                )
            )
        Right True -> pure (Right ())
        Right False ->
          pure
            ( Left
                ( Readiness.Progress
                    0
                    1
                    "Darwin build-memory process group still has a live member"
                )
            )
    onDeadline _ =
      ioError
        ( userError
            "Darwin build-memory process group retained a live member after its relayed streams closed"
        )

cleanupDarwinBuildMemoryProcess :: DarwinBuildMemoryProcess -> IO ()
cleanupDarwinBuildMemoryProcess spawned =
  cleanupDarwinBuildMemoryProcessParts
    (darwinBuildMemoryProcessHandle spawned)
    (darwinBuildMemoryProcessGroup spawned)
    [ darwinBuildMemoryStdoutHandle spawned,
      darwinBuildMemoryStderrHandle spawned
    ]
    [ darwinBuildMemoryStdoutThread spawned,
      darwinBuildMemoryStderrThread spawned
    ]

-- | Cleanup after the fixed observer has proved no live group member remains.
-- The numeric group is no longer an authority once the leader is reaped, so
-- this phase uses only the retained ProcessHandle and local relay resources.
cleanupDarwinBuildMemoryAfterLiveGroupAbsence ::
  DarwinBuildMemoryProcess ->
  IO ()
cleanupDarwinBuildMemoryAfterLiveGroupAbsence spawned =
  runCleanupsPreservingFailures
    [ void
        ( waitForToolchainProcess
            "post-observation Darwin build-memory cleanup"
            (darwinBuildMemoryProcessHandle spawned)
        ),
      cleanupDarwinBuildMemoryLocalResources spawned
    ]

cleanupDarwinBuildMemoryLocalResources :: DarwinBuildMemoryProcess -> IO ()
cleanupDarwinBuildMemoryLocalResources spawned =
  runCleanupsPreservingFailures
    [ closeHandleIfOpen (darwinBuildMemoryStdoutHandle spawned),
      closeHandleIfOpen (darwinBuildMemoryStderrHandle spawned),
      killThread (darwinBuildMemoryStdoutThread spawned),
      killThread (darwinBuildMemoryStderrThread spawned)
    ]

cleanupDarwinBuildMemoryProcessParts ::
  ProcessHandle ->
  CPid ->
  [Handle] ->
  [ThreadId] ->
  IO ()
cleanupDarwinBuildMemoryProcessParts processHandle processGroup handles threads =
  runCleanupsPreservingFailures
    [ ignoreMissingOrZombieGroup (signalProcessGroup sigCONT processGroup),
      ignoreMissingOrZombieGroup (signalProcessGroup sigKILL processGroup),
      ignoreMissingProcess (terminateProcess processHandle),
      mapM_ killThread threads,
      mapM_ closeHandleIfOpen handles,
      -- The fixed live-member observer runs before the leader is reaped, while
      -- that retained zombie/live identity still pins the numeric PGID.
      awaitDarwinBuildMemoryLiveGroupAbsence processGroup,
      void
        ( waitForToolchainProcess
            "Darwin build-memory cleanup"
            processHandle
        )
    ]

cleanupToolchainProcessGroupParts ::
  String ->
  ProcessHandle ->
  CPid ->
  [Handle] ->
  [ThreadId] ->
  IO ()
cleanupToolchainProcessGroupParts label processHandle processGroup handles threads =
  runCleanupsPreservingFailures
    [ ignoreMissingOrZombieGroup (signalProcessGroup sigCONT processGroup),
      ignoreMissingOrZombieGroup (signalProcessGroup sigKILL processGroup),
      ignoreMissingProcess (terminateProcess processHandle),
      mapM_ killThread threads,
      mapM_ closeHandleIfOpen handles,
      void
        ( waitForToolchainProcess
            (label <> " cleanup")
            processHandle
        )
    ]

waitForDarwinBuildMemoryProcess :: String -> ProcessHandle -> IO ExitCode
waitForDarwinBuildMemoryProcess = waitForToolchainProcess

waitForToolchainProcessLeader :: String -> ProcessHandle -> IO ExitCode
waitForToolchainProcessLeader =
  waitForToolchainProcessWithDeadline
    toolchainProcessWaitDeadline
    "fixed four-hour scheduler"

waitForToolchainProcess :: String -> ProcessHandle -> IO ExitCode
waitForToolchainProcess =
  waitForToolchainProcessWithDeadline
    darwinBuildMemoryCleanupDeadline
    "bounded reap"

-- | Poll the public nonblocking process API while masked. The only
-- interruptible point is the Readiness-owned delay between @Nothing@ results,
-- when an exited leader is still an unreaped zombie and therefore pins its
-- PID/PGID. A @Just@ result performs waitpid and closes the ProcessHandle under
-- the mask before the caller can disarm group-signaling cleanup.
waitForToolchainProcessWithDeadline ::
  Readiness.Deadline ->
  String ->
  String ->
  ProcessHandle ->
  IO ExitCode
waitForToolchainProcessWithDeadline deadline deadlineLabel label processHandle = do
  outcome <-
    Readiness.awaitProcessExitReadiness deadline processHandle
  Readiness.foldReadiness
    pure
    onDeadline
    onDeadline
    outcome
  where
    onDeadline _ =
      ioError
        ( userError
            (label <> " exceeded its " <> deadlineLabel <> " deadline")
        )

ignoreMissingOrZombieGroup :: IO () -> IO ()
ignoreMissingOrZombieGroup action =
  action `catch` \(failure :: IOException) ->
    unless
      (isDoesNotExistError failure || isPermissionError failure)
      (throwIO failure)

ignoreMissingProcess :: IO () -> IO ()
ignoreMissingProcess action =
  action `catch` \(failure :: IOException) ->
    unless (isDoesNotExistError failure) (throwIO failure)

closeHandleIfOpen :: Handle -> IO ()
closeHandleIfOpen handleValue = do
  closed <- hIsClosed handleValue
  unless closed (hClose handleValue)

exitCodeStatus :: ExitCode -> Int
exitCodeStatus exitCode =
  case exitCode of
    ExitSuccess -> 0
    ExitFailure status -> status

maybeToList :: Maybe value -> [value]
maybeToList maybeValue =
  case maybeValue of
    Just value -> [value]
    Nothing -> []

darwinBuildMemoryRelayChunkBytes :: Int
darwinBuildMemoryRelayChunkBytes = 32768

darwinBuildMemoryCleanupPollMicros :: Int
darwinBuildMemoryCleanupPollMicros = 50000

darwinBuildMemoryCleanupTimeoutMicros :: Int
darwinBuildMemoryCleanupTimeoutMicros = 15000000

darwinBuildMemoryCleanupDeadline :: Readiness.Deadline
darwinBuildMemoryCleanupDeadline =
  Readiness.budgetDeadline
    (darwinBuildMemoryCleanupTimeoutMicros `div` darwinBuildMemoryCleanupPollMicros)
    darwinBuildMemoryCleanupPollMicros

darwinBuildMemoryMaximumSamples :: Int
darwinBuildMemoryMaximumSamples = 14400

darwinBuildMemorySamplingDeadline :: Readiness.Deadline
darwinBuildMemorySamplingDeadline =
  Readiness.budgetDeadline
    darwinBuildMemoryMaximumSamples
    BuildMemory.darwinBuildMemorySampleIntervalMicros

toolchainProcessWaitDeadline :: Readiness.Deadline
toolchainProcessWaitDeadline =
  Readiness.budgetDeadline
    darwinBuildMemoryMaximumSamples
    BuildMemory.darwinBuildMemorySampleIntervalMicros

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
  BuildMemory.withToolchainSpawnAuthority (repoRoot paths) plan action

-- | Start one toolchain invocation under the region's derived ceiling.
--
-- The invocation comes from the closed 'ToolchainInvocation' vocabulary, so a
-- build assembled from a caller-supplied argument list is not a term. The
-- authority's single-flight token and ceiling remain held from the descriptor
-- precheck through fresh-group spawn, victim-rank adjustment, wait, normal
-- Cabal-leader reap, or exceptional group kill and bounded leader reap. Cabal
-- is the trusted scheduler and waits for its ordinary workers before exiting;
-- this path does not claim a safe post-reap descendant proof.
runToolchainCommand ::
  ToolchainSpawnAuthority s ->
  Maybe RuntimeMode ->
  ToolchainInvocation ->
  IO ()
runToolchainCommand authority _maybeRuntimeMode invocation = do
  paths <- discoverCliCommandPaths
  resolvedCommand <- resolveCliHostTool paths HostCabal
  exitCode <-
    BuildMemory.withBoundedToolchainChild authority $
      mask $ \_ -> do
        spawned <-
          spawnOwnedToolchainProcess
            paths
            authority
            invocation
            resolvedCommand
        onExceptionPreservingPrimary
          -- Phase 1 Sprint 1.21 isolates this child in a fresh process group so
          -- exceptional cleanup can signal an owned group without signalling the
          -- harness. That isolation also removed the child from the identity a
          -- held harness reservation authorizes by, which silently refused the
          -- cluster-owned suites' own `internal materialize-substrate` writes and
          -- cluster mutations. Delegating this exact group for the child's
          -- lifetime restores that authority without giving up the isolation.
          ( withDelegatedHarnessChildGroup
              paths
              (fromIntegral (ownedToolchainProcessGroup spawned))
              ( do
                  BuildMemory.applyToolchainChildVictimRank
                    authority
                    (ownedToolchainProcessGroup spawned)
                  waitForToolchainProcessLeader
                    (BuildMemory.toolchainInvocationLabel authority invocation)
                    (ownedToolchainProcessHandle spawned)
              )
          )
          (cleanupOwnedToolchainProcess authority invocation spawned)
  case exitCode of
    ExitSuccess -> pure ()
    _ -> exitWith exitCode

spawnOwnedToolchainProcess ::
  Paths ->
  ToolchainSpawnAuthority s ->
  ToolchainInvocation ->
  FilePath ->
  IO OwnedToolchainProcess
spawnOwnedToolchainProcess paths authority invocation resolvedCommand = do
  let label = BuildMemory.toolchainInvocationLabel authority invocation
  _ <- requireBoundedDescriptorSpace (label <> " process-group spawn")
  BuildMemory.requireToolchainInvocationProjectState authority invocation
  (_, _, _, processHandle) <-
    createProcess
      ( proc
          resolvedCommand
          (BuildMemory.toolchainInvocationArguments authority invocation)
      )
        { env = Just (cliSubprocessBaseEnvFor paths),
          cwd = Just (repoRoot paths),
          std_in = Inherit,
          std_out = Inherit,
          std_err = Inherit,
          close_fds = True,
          create_group = True
        }
  let cleanupBeforeGroup =
        cleanupUnidentifiedToolchainProcess label processHandle
  maybeProcessGroup <-
    onExceptionPreservingPrimary
      (getPid processHandle)
      cleanupBeforeGroup
  processGroup <-
    case maybeProcessGroup of
      Just observed -> pure observed
      Nothing ->
        onExceptionPreservingPrimary
          ( ioError
              ( userError
                  (label <> " exited before its process-group identity was observed")
              )
          )
          cleanupBeforeGroup
  let spawned = OwnedToolchainProcess processHandle processGroup
  onExceptionPreservingPrimary
    (validateFreshToolchainProcessGroup label processGroup)
    (cleanupOwnedToolchainProcess authority invocation spawned)
  pure spawned

validateFreshToolchainProcessGroup :: String -> CPid -> IO ()
validateFreshToolchainProcessGroup label processGroup = do
  observedGroup <- getProcessGroupIDOf processGroup
  unless (observedGroup == processGroup) $
    ioError
      ( userError
          (label <> " was not isolated in its requested fresh process group")
      )

cleanupUnidentifiedToolchainProcess :: String -> ProcessHandle -> IO ()
cleanupUnidentifiedToolchainProcess label processHandle =
  runCleanupsPreservingFailures
    [ ignoreMissingProcess (terminateProcess processHandle),
      void
        ( waitForToolchainProcess
            (label <> " unidentified-child cleanup")
            processHandle
        )
    ]

cleanupOwnedToolchainProcess ::
  ToolchainSpawnAuthority s ->
  ToolchainInvocation ->
  OwnedToolchainProcess ->
  IO ()
cleanupOwnedToolchainProcess authority invocation spawned =
  cleanupToolchainProcessGroupParts
    (BuildMemory.toolchainInvocationLabel authority invocation)
    (ownedToolchainProcessHandle spawned)
    (ownedToolchainProcessGroup spawned)
    []
    []

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
          HostGit
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
