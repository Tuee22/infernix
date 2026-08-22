module Main (main) where

import Control.Monad (unless)
import Data.List (isInfixOf, isPrefixOf)
import System.Directory
  ( canonicalizePath,
    createDirectoryIfMissing,
    doesFileExist,
    getCurrentDirectory,
  )
import System.Environment (getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.Posix.User
  ( getEffectiveUserID,
    getUserEntryForID,
    homeDirectory,
  )
import System.Process
  ( CreateProcess (cwd, env),
    proc,
    readCreateProcessWithExitCode,
  )

data FailingFixture = FailingFixture
  { fixtureTarget :: String,
    fixtureFile :: FilePath,
    fixtureDiagnosticClasses :: [String],
    fixtureProtectedSymbols :: [String]
  }

main :: IO ()
main = do
  repositoryRoot <- findRepositoryRoot
  userHome <- currentUserHome
  cabalExecutable <- findCabalExecutable userHome
  ghcExecutable <- findGhcExecutable userHome
  let childEnvironment = fixtureChildEnvironment userHome cabalExecutable
  let projectFile = repositoryRoot </> "test" </> "compile-fail" </> "cabal.project"
      buildDirectory = repositoryRoot </> ".build" </> "compile-fail"
      logDirectory = buildDirectory </> "logs"
  createDirectoryIfMissing True logDirectory
  mapM_
    (assertPassingFixture repositoryRoot cabalExecutable ghcExecutable childEnvironment projectFile buildDirectory logDirectory)
    passingFixtures
  mapM_
    (assertFailingFixture repositoryRoot cabalExecutable ghcExecutable childEnvironment projectFile buildDirectory logDirectory)
    failingFixtures
  putStrLn
    ( "compile-time capability fixtures passed: "
        <> show (length passingFixtures)
        <> " positive, "
        <> show (length failingFixtures)
        <> " negative"
    )

passingFixtures :: [String]
passingFixtures =
  [ "pass-matching-host",
    "pass-matching-pod",
    "pass-refined-route",
    "pass-compiled-route",
    "pass-ordered-subprocess-protocol",
    "pass-ordered-artifact-program",
    "pass-matching-requirement"
  ]

failingFixtures :: [FailingFixture]
failingFixtures =
  [ constructorFixture "fail-cannot-construct-memory-ceiling" "CannotConstructMemoryCeiling.hs" "MemoryCeiling",
    constructorFixture "fail-cannot-construct-memory-grant" "CannotConstructMemoryGrant.hs" "MemoryGrant",
    readFixture "fail-cannot-read-memory-ceiling" "CannotReadMemoryCeiling.hs" "MemoryCeiling",
    readFixture "fail-cannot-read-memory-grant" "CannotReadMemoryGrant.hs" "MemoryGrant",
    readFixture "fail-cannot-read-engine-route" "CannotReadEngineRoute.hs" "EngineRoute",
    readFixture "fail-cannot-read-host-memory-partition" "CannotReadHostMemoryPartition.hs" "HostMemoryPartition",
    readFixture "fail-cannot-read-model-memory-requirement" "CannotReadModelMemoryRequirement.hs" "ModelMemoryRequirement",
    nominalResourceFixture "fail-cannot-coerce-memory-ceiling-resource" "CannotCoerceMemoryCeilingResource.hs",
    nominalResourceFixture "fail-cannot-coerce-memory-grant-resource" "CannotCoerceMemoryGrantResource.hs",
    nominalResourceFixture "fail-cannot-coerce-enforcer-resource" "CannotCoerceEnforcerResource.hs",
    nominalResourceFixture "fail-cannot-coerce-enforcer-plan-resource" "CannotCoerceEnforcerPlanResource.hs",
    -- Phase 4 Sprint 4.38: the requirement is the quantity that used to feed
    -- both admission arms as one scalar. Its index is nominal, so neither a
    -- coercion nor a plain substitution can move a host quantity onto the
    -- device. The positive control is @pass-matching-requirement@.
    deviceResourceFixture
      "fail-cannot-coerce-model-memory-requirement-resource"
      "CannotCoerceModelMemoryRequirementResource.hs"
      ["HostRam", "NvidiaVram", "coerce"],
    deviceResourceFixture
      "fail-cannot-supply-host-requirement-for-device"
      "CannotSupplyHostRequirementForDevice.hs"
      ["HostRam", "NvidiaVram"],
    constructorFixture "fail-cannot-construct-executable-model" "CannotConstructExecutableModel.hs" "ExecutableModel",
    constructorFixture "fail-cannot-construct-raw-runtime-config" "CannotConstructRawRuntimeConfig.hs" "RawRuntimeConfig",
    hiddenModuleFixture "fail-cannot-import-cluster-command" "CannotImportClusterCommand.hs" "Infernix.Cluster.Command",
    hiddenModuleFixture "fail-cannot-import-cluster-lifecycle-lock" "CannotImportClusterLifecycleLock.hs" "Infernix.Cluster.LifecycleLock",
    hiddenModuleFixture "fail-cannot-import-cluster-subprocess" "CannotImportClusterSubprocess.hs" "Infernix.Cluster.Subprocess",
    removedExportsFixture
      "fail-cannot-import-cli-internal-subprocess-dispatch"
      "CannotImportCliInternalSubprocessDispatch.hs"
      ["dispatchInternalSubprocessMode"],
    hiddenModuleFixture "fail-cannot-import-execution-plan-internal" "CannotImportExecutionPlanInternal.hs" "Infernix.ExecutionPlan.Internal",
    hiddenModuleFixture "fail-cannot-import-process-identity-internal" "CannotImportProcessIdentityInternal.hs" "Infernix.ProcessIdentity.Internal",
    hiddenModuleFixture "fail-cannot-import-substrate-internal" "CannotImportSubstrateInternal.hs" "Infernix.Substrate.Internal",
    hiddenModuleFixture
      "fail-cannot-import-apple-silicon-internal"
      "CannotImportAppleSiliconInternal.hs"
      "Infernix.Engines.AppleSilicon.Internal",
    hiddenModuleFixture
      "fail-cannot-import-engine-artifact"
      "CannotImportEngineArtifact.hs"
      "Infernix.Engines.Artifact",
    hiddenModuleFixture
      "fail-cannot-import-engine-artifact-capability"
      "CannotImportEngineArtifactCapability.hs"
      "Infernix.Engines.Artifact.Capability",
    hiddenModuleFixture
      "fail-cannot-import-engine-provisioning"
      "CannotImportEngineProvisioning.hs"
      "Infernix.Engines.Provisioning",
    hiddenModuleFixture
      "fail-cannot-import-engine-provisioning-internal"
      "CannotImportEngineProvisioningInternal.hs"
      "Infernix.Engines.Provisioning.Internal",
    hiddenModuleFixture
      "fail-cannot-import-python"
      "CannotImportPython.hs"
      "Infernix.Python",
    hiddenModuleFixture
      "fail-cannot-import-raw-python-worker-launch"
      "CannotImportRawPythonWorkerLaunch.hs"
      "Infernix.Runtime.CappedEngine",
    hiddenModuleFixture
      "fail-cannot-import-capped-engine-internal"
      "CannotImportCappedEngineInternal.hs"
      "Infernix.Runtime.CappedEngine.Internal",
    removedExportFixture
      "fail-cannot-import-raw-apple-installer"
      "CannotImportRawAppleInstaller.hs"
      "materializeMetalEngineArtifact",
    constructorFixture
      "fail-cannot-construct-linux-native-artifact"
      "CannotConstructLinuxNativeArtifact.hs"
      "LinuxNativeEngineArtifact",
    removedExportFixture
      "fail-cannot-import-raw-linux-native-materializer"
      "CannotImportRawLinuxNativeMaterializer.hs"
      "materializeLinuxNativeEngineArtifact",
    removedExportFixture
      "fail-cannot-read-raw-linux-native-artifact-fields"
      "CannotReadRawLinuxNativeArtifactFields.hs"
      "linuxNativeEntrypoint",
    removedExportsFixture
      "fail-cannot-import-raw-demo-config"
      "CannotImportRawDemoConfig.hs"
      ["decodeDemoConfigFile", "decodeBootstrapDemoConfigFile", "validateDemoConfig"],
    removedExportFixture
      "fail-removed-worker-native-args"
      "RemovedWorkerNativeArgs.hs"
      "nativeRunnerArgs",
    removedExportFixture
      "fail-removed-worker-native-roots"
      "RemovedWorkerNativeRoots.hs"
      "nativeEngineInstallRootCandidates",
    removedExportsFixture
      "fail-cannot-import-raw-pulsar-routing"
      "CannotImportRawPulsarRouting.hs"
      ["serviceConsumerSubscriptionTypeForTopic", "startupTopicsForDemoConfig"],
    removedExportFixture "fail-cannot-import-removed-models-routing" "CannotImportRemovedModelsRouting.hs" "enginePoolTopicForMode",
    typeMismatchFixture "fail-raw-pulsar-publish" "RawPulsarPublish.hs" "publishInferenceRequest",
    typeMismatchFixture "fail-raw-pulsar-drain" "RawPulsarDrain.hs" "drainTopic",
    typeMismatchFixture "fail-raw-model-bootstrap-publish" "RawModelBootstrapPublish.hs" "publishModelBootstrapRequest",
    typeMismatchFixture "fail-host-enforcer-pod-grant" "HostEnforcerPodGrant.hs" "PodRam",
    typeMismatchFixture "fail-vram-enforcer-host-grant" "VramEnforcerHostGrant.hs" "NvidiaVram",
    typeMismatchFixture "fail-vram-enforcer-pod-grant" "VramEnforcerPodGrant.hs" "NvidiaVram",
    typeMismatchFixture "fail-pod-enforcer-vram-grant" "PodEnforcerVramGrant.hs" "PodRam",
    typeMismatchFixture "fail-compiled-plan-is-not-runtime-plan" "CompiledPlanIsNotRuntimePlan.hs" "CompiledRuntimePlan",
    removedExportFixture
      "fail-cannot-admit-without-observation"
      "CannotAdmitWithoutObservation.hs"
      "RuntimeObservation",
    removedExportFixture
      "fail-compiled-placement-has-no-resources"
      "CompiledPlacementHasNoResources.hs"
      "compiledPlacementEnforcedResources",
    typeMismatchFixture "fail-planned-enforcer-is-not-live" "PlannedEnforcerIsNotLive.hs" "EnforcerPlan",
    typeMismatchFixture "fail-raw-worker-route" "RawWorkerRoute.hs" "ModelDescriptor",
    typeMismatchFixture "fail-cannot-coerce-cluster-teardown-authority" "CannotCoerceClusterTeardownAuthority.hs" "ClusterTeardownAuthority",
    typeMismatchFixture "fail-cannot-coerce-cluster-lifecycle-lease" "CannotCoerceClusterLifecycleLease.hs" "Lease",
    constructorFixture
      "fail-cannot-construct-toolchain-spawn-authority"
      "CannotConstructToolchainSpawnAuthority.hs"
      "ToolchainSpawnAuthority",
    typeMismatchFixture
      "fail-cannot-escape-toolchain-spawn-authority"
      "CannotEscapeToolchainSpawnAuthority.hs"
      "ToolchainSpawnAuthority",
    typeMismatchFixture
      "fail-cannot-substitute-toolchain-spawn-region"
      "CannotSubstituteToolchainSpawnRegion.hs"
      "ToolchainSpawnAuthority",
    typeMismatchFixture
      "fail-cannot-coerce-toolchain-spawn-authority"
      "CannotCoerceToolchainSpawnAuthority.hs"
      "ToolchainSpawnAuthority",
    typeMismatchFixture
      "fail-cannot-coerce-darwin-build-memory-validation-authority"
      "CannotCoerceDarwinBuildMemoryValidationAuthority.hs"
      "DarwinBuildMemoryValidationAuthority",
    typeMismatchFixture
      "fail-cannot-claim-unenforced-address-space"
      "CannotClaimUnenforcedAddressSpace.hs"
      "BuildMemoryBound",
    typeMismatchFixture "fail-cannot-escape-cluster-teardown-authority" "CannotEscapeClusterTeardownAuthority.hs" "ClusterTeardownAuthority",
    typeMismatchFixture "fail-cannot-reuse-cluster-teardown-authority" "CannotReuseClusterTeardownAuthority.hs" "ClusterTeardownAuthority",
    typeMismatchFixture
      "fail-cannot-substitute-cluster-teardown-owner"
      "CannotSubstituteClusterTeardownOwner.hs"
      "ClusterTeardownAuthority",
    typeMismatchFixture "fail-skip-subprocess-lease-phase" "SkipSubprocessLeasePhase.hs" "LeaseDurable",
    typeMismatchFixture
      "fail-skip-subprocess-supervisor-observation"
      "SkipSubprocessSupervisorObservation.hs"
      "SupervisorCustodyEvidence",
    typeMismatchFixture
      "fail-skip-subprocess-pin-custody-observation"
      "SkipSubprocessPinCustodyObservation.hs"
      "PinCustodyEvidence",
    typeMismatchFixture
      "fail-skip-subprocess-final-ready-observation"
      "SkipSubprocessFinalReadyObservation.hs"
      "SupervisorReadyEvidence",
    typeMismatchFixture
      "fail-skip-subprocess-durable-publication"
      "SkipSubprocessDurablePublication.hs"
      "ActivityPublication",
    typeMismatchFixture "fail-escape-subprocess-session" "EscapeSubprocessSession.hs" "Session",
    linearityFixture "fail-reuse-subprocess-start-authority" "ReuseSubprocessStartAuthority.hs" "session",
    constructorFixture
      "fail-cannot-construct-subprocess-anchor-control"
      "CannotConstructSubprocessAnchorControl.hs"
      "AnchorControl",
    constructorFixture
      "fail-cannot-construct-supervisor-ready-evidence"
      "CannotConstructSupervisorReadyEvidence.hs"
      "SupervisorReadyEvidence",
    constructorFixture
      "fail-cannot-construct-supervisor-custody-evidence"
      "CannotConstructSupervisorCustodyEvidence.hs"
      "SupervisorCustodyEvidence",
    constructorFixture
      "fail-cannot-construct-pin-custody-evidence"
      "CannotConstructPinCustodyEvidence.hs"
      "PinCustodyEvidence",
    constructorFixture
      "fail-cannot-construct-activity-publication"
      "CannotConstructActivityPublication.hs"
      "ActivityPublication",
    typeMismatchFixture
      "fail-reuse-artifact-session"
      "ReuseArtifactSession.hs"
      "ValidatedEngineArtifact",
    FailingFixture
      "fail-skip-artifact-reap"
      "SkipArtifactReap.hs"
      typeMismatchDiagnostics
      ["ArtifactReady", "ArtifactReaped"],
    FailingFixture
      "fail-skip-artifact-phase"
      "SkipArtifactPhase.hs"
      typeMismatchDiagnostics
      ["ArtifactReady", "ArtifactReaped"],
    FailingFixture
      "fail-escape-artifact-nested-io"
      "EscapeArtifactNestedIO.hs"
      typeMismatchDiagnostics
      ["ArtifactTerminalOutcome", "IO ()"],
    removedExportFixture
      "fail-escape-materialization-authority"
      "EscapeMaterializationAuthority.hs"
      "MaterializationAuthority",
    removedExportFixture
      "fail-capture-materialization-authority-in-closure"
      "CaptureMaterializationAuthorityInClosure.hs"
      "withEngineMaterializationLock",
    removedExportFixture
      "fail-cannot-construct-materialization-authority"
      "CannotConstructMaterializationAuthority.hs"
      "MaterializationAuthority",
    removedExportFixture
      "fail-write-artifact-without-authority"
      "WriteArtifactWithoutAuthority.hs"
      "reconcileEngineArtifactRoot",
    removedExportFixture
      "fail-arbitrary-installed-artifact-validation"
      "ArbitraryInstalledArtifactValidation.hs"
      "installEngineArtifactRootWithExpectedDigestAndValidation",
    hiddenModuleFixture
      "fail-cannot-import-apple-materialization-transaction"
      "CannotImportAppleMaterializationTransaction.hs"
      "Infernix.Engines.AppleSilicon.MaterializationTransaction",
    removedExportFixture
      "fail-cannot-construct-apple-materialization-request"
      "CannotConstructAppleMaterializationRequest.hs"
      "MaterializationRequest",
    removedExportFixture
      "fail-removed-apple-phase-transition"
      "RemovedApplePhaseTransition.hs"
      "hydrateCandidate",
    hiddenModuleFixture
      "fail-cannot-import-artifact-transaction-kernel"
      "CannotImportArtifactTransactionKernel.hs"
      "Infernix.Engines.Artifact.Internal",
    hiddenModuleFixture
      "fail-cannot-import-materialization-lock-kernel"
      "CannotImportMaterializationLockKernel.hs"
      "Infernix.Engines.MaterializationLock.Internal",
    hiddenModuleFixture
      "fail-cannot-import-download-cache-lock-kernel"
      "CannotImportDownloadCacheLockKernel.hs"
      "Infernix.Engines.DownloadCacheLock.Internal",
    hiddenModuleFixture
      "fail-cannot-import-python-mutation-lock-kernel"
      "CannotImportPythonMutationLockKernel.hs"
      "Infernix.Python.MutationLock.Internal",
    hiddenModuleFixture
      "fail-cannot-import-cluster-subprocess-protocol"
      "CannotImportClusterSubprocessProtocol.hs"
      "Infernix.Cluster.Subprocess.Protocol",
    hiddenModuleFixture
      "fail-cannot-import-cluster-subprocess-activity"
      "CannotImportClusterSubprocessActivity.hs"
      "Infernix.Cluster.Subprocess.Activity",
    hiddenModuleFixture "fail-raw-capped-launch" "RawCappedLaunch.hs" "Infernix.Runtime.CappedEngine",
    removedExportFixture
      "fail-cannot-construct-engine-topic-capability"
      "CannotConstructEngineTopicCapability.hs"
      "EngineTopicCapability"
  ]

constructorFixture :: String -> FilePath -> String -> FailingFixture
constructorFixture target sourceFile =
  FailingFixture target sourceFile constructorDiagnostics . pure

hiddenModuleFixture :: String -> FilePath -> String -> FailingFixture
hiddenModuleFixture target sourceFile =
  FailingFixture target sourceFile hiddenModuleDiagnostics . pure

typeMismatchFixture :: String -> FilePath -> String -> FailingFixture
typeMismatchFixture target sourceFile =
  FailingFixture target sourceFile typeMismatchDiagnostics . pure

nominalResourceFixture :: String -> FilePath -> FailingFixture
nominalResourceFixture target sourceFile =
  FailingFixture
    target
    sourceFile
    typeMismatchDiagnostics
    ["HostRam", "PodRam", "coerce"]

-- | Phase 4 Sprint 4.38: the device twin of 'nominalResourceFixture'. The
-- expected symbols are supplied rather than fixed because a host-to-device
-- rejection names @NvidiaVram@ where a host-to-pod rejection names @PodRam@,
-- and a fixture that accepted either would pass on a diagnostic about the
-- wrong pair of resources.
deviceResourceFixture :: String -> FilePath -> [String] -> FailingFixture
deviceResourceFixture target sourceFile =
  FailingFixture target sourceFile typeMismatchDiagnostics

linearityFixture :: String -> FilePath -> String -> FailingFixture
linearityFixture target sourceFile =
  FailingFixture target sourceFile linearityDiagnostics . pure

readFixture :: String -> FilePath -> String -> FailingFixture
readFixture target sourceFile =
  FailingFixture target sourceFile readDiagnostics . pure

removedExportFixture :: String -> FilePath -> String -> FailingFixture
removedExportFixture target sourceFile =
  FailingFixture target sourceFile removedExportDiagnostics . pure

removedExportsFixture :: String -> FilePath -> [String] -> FailingFixture
removedExportsFixture target sourceFile =
  FailingFixture target sourceFile removedExportDiagnostics

constructorDiagnostics :: [String]
constructorDiagnostics =
  [ "Data constructor not in scope",
    "not in scope",
    "Illegal term-level use of the type constructor"
  ]

hiddenModuleDiagnostics :: [String]
hiddenModuleDiagnostics =
  [ "hidden module",
    "Could not load module",
    "Could not find module"
  ]

removedExportDiagnostics :: [String]
removedExportDiagnostics =
  [ "does not export",
    "not exported"
  ]

typeMismatchDiagnostics :: [String]
typeMismatchDiagnostics =
  [ "Couldn't match type",
    "Could not match type",
    "Couldn't match expected type",
    "Could not match expected type",
    "Couldn't match representation of type",
    "Could not match representation of type"
  ]

linearityDiagnostics :: [String]
linearityDiagnostics =
  [ "Couldn't match type 'Many' with 'One'",
    "Could not match type 'Many' with 'One'",
    "multiplicity"
  ]

readDiagnostics :: [String]
readDiagnostics =
  [ "No instance for",
    "No instance"
  ]

assertPassingFixture ::
  FilePath ->
  FilePath ->
  FilePath ->
  [(String, String)] ->
  FilePath ->
  FilePath ->
  FilePath ->
  String ->
  IO ()
assertPassingFixture repositoryRoot cabalExecutable ghcExecutable childEnvironment projectFile buildDirectory logDirectory target = do
  (exitCode, diagnostic) <-
    runFixtureBuild repositoryRoot cabalExecutable ghcExecutable childEnvironment projectFile buildDirectory target
  writeFile (logDirectory </> target <> ".log") diagnostic
  unless (exitCode == ExitSuccess) $
    failWithDiagnostic ("compile-pass fixture failed: " <> target) diagnostic

assertFailingFixture ::
  FilePath ->
  FilePath ->
  FilePath ->
  [(String, String)] ->
  FilePath ->
  FilePath ->
  FilePath ->
  FailingFixture ->
  IO ()
assertFailingFixture repositoryRoot cabalExecutable ghcExecutable childEnvironment projectFile buildDirectory logDirectory fixture = do
  (exitCode, diagnostic) <-
    runFixtureBuild
      repositoryRoot
      cabalExecutable
      ghcExecutable
      childEnvironment
      projectFile
      buildDirectory
      (fixtureTarget fixture)
  writeFile (logDirectory </> fixtureTarget fixture <> ".log") diagnostic
  case exitCode of
    ExitSuccess ->
      failWithDiagnostic
        ("compile-fail fixture unexpectedly compiled: " <> fixtureTarget fixture)
        diagnostic
    ExitFailure _ -> pure ()
  unless (fixtureFile fixture `isInfixOf` diagnostic) $
    failWithDiagnostic
      ("compile-fail fixture failed outside its source file: " <> fixtureTarget fixture)
      diagnostic
  unless (any (`isInfixOf` diagnostic) (fixtureDiagnosticClasses fixture)) $
    failWithDiagnostic
      ("compile-fail fixture produced the wrong diagnostic class: " <> fixtureTarget fixture)
      diagnostic
  let diagnosticWithoutFixtureIdentifiers =
        removeAll
          (fixtureFile fixture)
          (removeAll (fixtureTarget fixture) diagnostic)
  unless
    ( all
        (`isInfixOf` diagnosticWithoutFixtureIdentifiers)
        (fixtureProtectedSymbols fixture)
    )
    $ failWithDiagnostic
      ("compile-fail fixture diagnostic omitted a protected symbol: " <> fixtureTarget fixture)
      diagnostic

removeAll :: String -> String -> String
removeAll needle haystack
  | null needle = haystack
  | otherwise = go haystack
  where
    go [] = []
    go remaining@(character : suffix)
      | needle `isPrefixOf` remaining =
          go (drop (length needle) remaining)
      | otherwise =
          character : go suffix

-- | The nested fixture build.
--
-- The compiler is named by absolute path on the command line, not left to the
-- project file's @with-compiler:@ to resolve through the child @PATH@. A bare
-- program name is resolved against whatever search path the child happens to
-- have, which is exactly the ambient dependency this repository refuses
-- everywhere else, and it fails on the lane whose deterministic launcher path
-- does not carry the toolchain: the launcher image has the compiler, and the
-- nested Cabal still reported that it could not find one. The command line also
-- takes precedence over the project file, which is the same reason the memory
-- account is passed here rather than left in @cabal.project@.
runFixtureBuild ::
  FilePath ->
  FilePath ->
  FilePath ->
  [(String, String)] ->
  FilePath ->
  FilePath ->
  String ->
  IO (ExitCode, String)
runFixtureBuild repositoryRoot cabalExecutable ghcExecutable childEnvironment projectFile buildDirectory target = do
  let command =
        ( proc
            cabalExecutable
            [ "+RTS",
              "-M1024M",
              "-RTS",
              "build",
              "--project-file=" <> projectFile,
              "--builddir=" <> buildDirectory,
              "infernix-compile-fixtures:exe:" <> target,
              "--jobs=1",
              "--with-compiler=" <> ghcExecutable,
              "--ghc-options=+RTS -M2048M -xr6144M -RTS"
            ]
        )
          { cwd = Just repositoryRoot,
            env = Just childEnvironment
          }
  (exitCode, stdoutText, stderrText) <- readCreateProcessWithExitCode command ""
  pure (exitCode, stdoutText <> stderrText)

-- | The compiler the nested project pins, resolved to an absolute path from a
-- fixed candidate list. The versioned name is preferred so a host carrying
-- several compilers still gets the pinned one; a plain @ghc@ is accepted after
-- it because that is what the governed lanes install.
findGhcExecutable :: FilePath -> IO FilePath
findGhcExecutable userHome = do
  maybeExecutable <-
    firstExistingFile
      [ userHome </> ".ghcup" </> "bin" </> "ghc-9.12.4",
        userHome </> ".ghcup" </> "bin" </> "ghc",
        "/opt/homebrew/bin/ghc-9.12.4",
        "/opt/homebrew/bin/ghc",
        "/usr/local/bin/ghc-9.12.4",
        "/usr/local/bin/ghc",
        "/usr/bin/ghc-9.12.4",
        "/usr/bin/ghc"
      ]
  case maybeExecutable of
    Nothing ->
      fail
        ( "the nested compile fixtures require the pinned compiler; none of the fixed candidates under "
            <> userHome
            <> "/.ghcup/bin, /opt/homebrew/bin, /usr/local/bin, or /usr/bin exists"
        )
    Just executable -> pure executable

currentUserHome :: IO FilePath
currentUserHome =
  homeDirectory <$> (getUserEntryForID =<< getEffectiveUserID)

findCabalExecutable :: FilePath -> IO FilePath
findCabalExecutable userHome = do
  maybeExecutable <-
    firstExistingFile
      [ userHome </> ".ghcup" </> "bin" </> "cabal",
        userHome </> ".cabal" </> "bin" </> "cabal",
        "/opt/homebrew/bin/cabal",
        "/usr/local/bin/cabal",
        "/usr/bin/cabal"
      ]
  case maybeExecutable of
    Nothing ->
      fail
        "compile-time capability fixtures require cabal at ~/.ghcup/bin/cabal, ~/.cabal/bin/cabal, or a supported fixed system path"
    Just executable -> canonicalizePath executable

-- The nested fixture compiler is a separate serialized toolchain surface. Its
-- environment and every memory-bearing operand are fixed here: one 2048 MiB
-- compiler, plus the outer Cabal, runner, nested Cabal, and nested auxiliary at
-- the 1024 MiB control cap. The 6144 MiB peak is inside the current outer
-- 8192 MiB account without reading or extending the caller's environment.
fixtureChildEnvironment :: FilePath -> FilePath -> [(String, String)]
fixtureChildEnvironment userHome cabalExecutable =
  [ ("HOME", userHome),
    ( "PATH",
      joinPathEntries
        [ takeDirectory cabalExecutable,
          userHome </> ".cabal" </> "bin",
          "/opt/homebrew/bin",
          "/usr/local/bin",
          "/usr/bin",
          "/bin"
        ]
    ),
    ("GHCRTS", "-M1024M"),
    ("LANG", "C.UTF-8"),
    ("LC_ALL", "C.UTF-8")
  ]

joinPathEntries :: [FilePath] -> String
joinPathEntries entries =
  case entries of
    [] -> ""
    firstEntry : remaining -> foldl (\joined entry -> joined <> ":" <> entry) firstEntry remaining

firstExistingFile :: [FilePath] -> IO (Maybe FilePath)
firstExistingFile candidates =
  case candidates of
    [] -> pure Nothing
    candidate : remaining -> do
      exists <- doesFileExist candidate
      if exists
        then pure (Just candidate)
        else firstExistingFile remaining

findRepositoryRoot :: IO FilePath
findRepositoryRoot = do
  currentDirectory <- getCurrentDirectory
  executablePath <- getExecutablePath
  currentRoot <- findRootFrom currentDirectory
  case currentRoot of
    Just root -> pure root
    Nothing -> do
      executableRoot <- findRootFrom (takeDirectory executablePath)
      maybe
        (fail "unable to locate infernix.cabal and test/compile-fail/cabal.project")
        pure
        executableRoot

findRootFrom :: FilePath -> IO (Maybe FilePath)
findRootFrom start = canonicalizePath start >>= search
  where
    search candidate = do
      hasPackage <- doesFileExist (candidate </> "infernix.cabal")
      hasFixtures <- doesFileExist (candidate </> "test" </> "compile-fail" </> "cabal.project")
      if hasPackage && hasFixtures
        then pure (Just candidate)
        else
          let parent = takeDirectory candidate
           in if parent == candidate
                then pure Nothing
                else search parent

failWithDiagnostic :: String -> String -> IO a
failWithDiagnostic message diagnostic =
  fail (message <> "\n" <> tailLines 80 diagnostic)

tailLines :: Int -> String -> String
tailLines lineCount =
  unlines . reverse . take lineCount . reverse . lines
