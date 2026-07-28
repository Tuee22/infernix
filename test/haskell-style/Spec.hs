module Main (main) where

import Control.Monad (unless, when)
import Infernix.Lint.HaskellStyle
  ( appleArtifactProvisioningViolations,
    appleClosureFixtureOwnershipViolations,
    appleMaterializationTransactionOwnershipViolations,
    artifactCapabilityBoundaryViolations,
    artifactWriterBoundaryViolations,
    boundedEngineOutputViolations,
    cappedEngineBoundaryViolations,
    linuxNativeMaterializationBoundaryViolations,
    nativeArtifactInvocationKernelOwnershipViolations,
    provisioningKernelOwnershipViolations,
    runHaskellStyleLint,
  )

main :: IO ()
main = do
  assertAppleArtifactProvisioningBoundary
  assertAppleClosureFixtureOwnership
  assertAppleMaterializationTransactionOwnership
  assertArtifactCapabilityBoundary
  assertArtifactWriterBoundary
  assertBoundedEngineOutput
  assertCappedEngineBoundary
  assertLinuxNativeMaterializationBoundary
  assertNativeArtifactInvocationKernelOwnership
  assertProvisioningKernelOwnership
  runHaskellStyleLint

assertAppleClosureFixtureOwnership :: IO ()
assertAppleClosureFixtureOwnership = do
  let fixtureUse =
        [ (1, "AppleInternal.inspectMachOFixtureForTest bytes"),
          (2, "AppleInternal.resolveMachOPathsFixtureForTest root executable graph")
        ]
  when
    ( null
        ( appleClosureFixtureOwnershipViolations
            "src/Infernix/Runtime/Worker.hs"
            fixtureUse
        )
    )
    (fail "production code may not invoke the Apple Mach-O fixture interpreter")
  mapM_
    ( \owner ->
        unless
          ( null
              ( appleClosureFixtureOwnershipViolations
                  owner
                  fixtureUse
              )
          )
          (fail ("Apple closure ownership lint rejected " <> owner))
    )
    [ "src/Infernix/Engines/AppleSilicon/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  unless
    ( null
        ( appleClosureFixtureOwnershipViolations
            "test/apple-materializer/Spec.hs"
            fixtureUse
        )
    )
    (fail "Apple closure ownership lint must permit the dedicated test component")

assertAppleMaterializationTransactionOwnership :: IO ()
assertAppleMaterializationTransactionOwnership = do
  let rawTransactionAccess =
        [ (1, "import Infernix.Engines.AppleSilicon.MaterializationTransaction"),
          (2, "request = MaterializationRequest { completeCandidate = action }"),
          (3, "runMaterializationTransaction bracket request"),
          (4, "closedMaterializationRequest prepare recover cleanup write complete"),
          (5, "session = AppleMaterializationSession"),
          (6, "beginAppleMaterialization"),
          (7, "prepareMetalEngineCandidate writer grant deadlines installRoot tempRoot artifact session"),
          (8, "writeMetalEngineCandidatePayload writer paths tempRoot artifact session"),
          (9, "completeMetalEngineCandidate cacheWriter writer hook paths grant deadlines installRoot tempRoot artifact session"),
          (10, "cleanupMetalEngineCandidate writer grant deadlines tempRoot artifact session")
        ]
  when
    ( null
        ( appleMaterializationTransactionOwnershipViolations
            "src/Infernix/Runtime/Worker.hs"
            rawTransactionAccess
        )
    )
    (fail "production callers may not access the Apple transaction kernel")
  mapM_
    ( \owner ->
        unless
          ( null
              ( appleMaterializationTransactionOwnershipViolations
                  owner
                  rawTransactionAccess
              )
          )
          (fail ("Apple transaction ownership lint rejected " <> owner))
    )
    ["src/Infernix/Engines/AppleSilicon/Internal.hs"]
  unless
    ( null
        ( appleMaterializationTransactionOwnershipViolations
            "test/apple-materializer/Spec.hs"
            rawTransactionAccess
        )
    )
    (fail "Apple transaction ownership lint must stay scoped to production")
  unless
    ( null
        ( appleMaterializationTransactionOwnershipViolations
            "src/Infernix/Runtime/Worker.hs"
            [ (1, "-- MaterializationRequest"),
              (2, "description = \"runMaterializationTransaction\"")
            ]
        )
    )
    (fail "Apple transaction ownership lint must ignore comments and strings")

assertProvisioningKernelOwnership :: IO ()
assertProvisioningKernelOwnership = do
  let rawKernelUses =
        [ (1, "Subprocess.observeProvisioningMutationRoot root"),
          (2, "Subprocess.provisioningCreateDirectoryLeaf root parents leaf"),
          (3, "Subprocess.provisioningRemoveTreeLeaf root parents leaf"),
          (4, "Subprocess.provisioningRenameSiblingDirectory root parents source destination"),
          (5, "Subprocess.provisioningRenameSiblingRegularFile root parents source destination"),
          (6, "Subprocess.runProvisioningFilesystemMutation environment timeout mutation"),
          (7, "Subprocess.compileProvisioningCommand command environment timeout"),
          (8, "Subprocess.compileProvisioningCommandWithExecutable command executable environment timeout"),
          (9, "Subprocess.compileProvisioningCommandWithExecutableInMutationRoot command root executable environment timeout"),
          (10, "Subprocess.resolveProvisioningCommandExecutable command environment")
        ]
      nonOwner = "src/Infernix/Runtime/Worker.hs"
      owners =
        [ "src/Infernix/Cluster/Subprocess.hs",
          "src/Infernix/Engines/Artifact/Activation.hs",
          "src/Infernix/Engines/Provisioning.hs"
        ]
  mapM_
    ( \rawUse ->
        when
          ( null
              ( provisioningKernelOwnershipViolations
                  nonOwner
                  [rawUse]
              )
          )
          (fail ("production caller may not use provisioning kernel token: " <> snd rawUse))
    )
    rawKernelUses
  mapM_
    ( \owner ->
        unless
          ( null
              ( provisioningKernelOwnershipViolations
                  owner
                  rawKernelUses
              )
          )
          (fail ("provisioning kernel ownership lint rejected " <> owner))
    )
    owners
  unless
    ( null
        ( provisioningKernelOwnershipViolations
            "test/integration/Spec.hs"
            rawKernelUses
        )
    )
    (fail "provisioning kernel ownership lint must stay scoped to production")
  unless
    ( null
        ( provisioningKernelOwnershipViolations
            nonOwner
            [ (1, "-- compileProvisioningCommand"),
              (2, "description = \"runProvisioningFilesystemMutation\"")
            ]
        )
    )
    (fail "provisioning kernel ownership lint must ignore comments and strings")

assertNativeArtifactInvocationKernelOwnership :: IO ()
assertNativeArtifactInvocationKernelOwnership = do
  let rawKernelUses =
        [ (1, "plan :: NativeArtifactInvocationPlan"),
          (2, "plan = Subprocess.nativeArtifactInvocationPlan model engine family adapter mode input object cache output inputFile"),
          (3, "Subprocess.runBoundedNativeArtifact executableModel artifact plan environment")
        ]
      nonOwner = "src/Infernix/Runtime/Worker.hs"
      owners =
        [ "src/Infernix/Cluster/Subprocess.hs",
          "src/Infernix/Runtime/CappedEngine/Internal.hs"
        ]
  mapM_
    ( \rawUse ->
        when
          ( null
              ( nativeArtifactInvocationKernelOwnershipViolations
                  nonOwner
                  [rawUse]
              )
          )
          (fail ("production caller may not use native-artifact invocation kernel token: " <> snd rawUse))
    )
    rawKernelUses
  mapM_
    ( \owner ->
        unless
          ( null
              ( nativeArtifactInvocationKernelOwnershipViolations
                  owner
                  rawKernelUses
              )
          )
          (fail ("native-artifact invocation ownership lint rejected " <> owner))
    )
    owners
  unless
    ( null
        ( nativeArtifactInvocationKernelOwnershipViolations
            "test/unit/Spec.hs"
            rawKernelUses
        )
    )
    (fail "native-artifact invocation ownership lint must stay scoped to production")
  unless
    ( null
        ( nativeArtifactInvocationKernelOwnershipViolations
            nonOwner
            [ (1, "-- runBoundedNativeArtifact"),
              (2, "description = \"NativeArtifactInvocationPlan\"")
            ]
        )
    )
    (fail "native-artifact invocation ownership lint must ignore comments and strings")

assertArtifactCapabilityBoundary :: IO ()
assertArtifactCapabilityBoundary = do
  let rawCapabilityImports =
        [ [(1, "import Infernix.Engines.Artifact.Capability")],
          [(1, "import qualified Infernix.Engines.Artifact.Capability as Capability")],
          [(1, "import Infernix.Engines.Artifact.Capability qualified as Capability")],
          [ (1, "import"),
            (2, "  qualified"),
            (3, "  Infernix.Engines.Artifact.Capability"),
            (4, "  as Capability")
          ]
        ]
      validationBoundaryUse =
        [(1, "Artifact.withFirstValidatedEngineArtifact identity expectation roots session")]
      workerFile = "src/Infernix/Runtime/Worker.hs"
      representationOwners =
        [ "src/Infernix/Engines/Artifact/Internal.hs",
          "src/Infernix/Runtime/CappedEngine/Internal.hs"
        ]
      boundaryOwners =
        "src/Infernix/Engines/Artifact.hs" : representationOwners
  mapM_
    ( \rawCapabilityImport ->
        when
          ( null
              ( artifactCapabilityBoundaryViolations
                  workerFile
                  rawCapabilityImport
              )
          )
          (fail "engine worker may not import the artifact capability representation")
    )
    rawCapabilityImports
  when
    ( null
        ( artifactCapabilityBoundaryViolations
            workerFile
            validationBoundaryUse
        )
    )
    (fail "engine worker may not enter the validated artifact boundary")
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactCapabilityBoundaryViolations
                  owner
                  (concat rawCapabilityImports)
              )
          )
          (fail ("artifact capability lint rejected its kernel owner " <> owner))
    )
    representationOwners
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactCapabilityBoundaryViolations
                  owner
                  validationBoundaryUse
              )
          )
          (fail ("artifact capability lint rejected its boundary owner " <> owner))
    )
    boundaryOwners
  when
    ( null
        ( artifactCapabilityBoundaryViolations
            "src/Infernix/Engines/Artifact.hs"
            (concat rawCapabilityImports)
        )
    )
    (fail "public artifact facade may not import the constructor-bearing representation")
  unless
    ( null
        ( artifactCapabilityBoundaryViolations
            "test/artifact-transaction/Spec.hs"
            (concat rawCapabilityImports <> validationBoundaryUse)
        )
    )
    (fail "artifact capability ownership lint must stay scoped to production sources")
  unless
    ( null
        ( artifactCapabilityBoundaryViolations
            workerFile
            [ (1, "-- import Infernix.Engines.Artifact.Capability"),
              (2, "description = \"withFirstValidatedEngineArtifact\"")
            ]
        )
    )
    (fail "artifact capability lint must ignore policy tokens in comments and string literals")

assertArtifactWriterBoundary :: IO ()
assertArtifactWriterBoundary = do
  let rawTransactionAccess =
        [ (1, "Artifact.reconcileEngineArtifactRoot installRoot"),
          (2, "Artifact.installEngineArtifactRootWithExpectedDigest installRoot candidateRoot digest"),
          (3, "Artifact.withEngineArtifactActivation authority installRoot candidateRoot digest continuation"),
          (4, "Artifact.finishEngineArtifactActivation CommitArtifactActivation activation"),
          (5, "Artifact.activateAppleEngineArtifactWithInstalledSmoke authority environment deadline adapter installRoot candidateRoot digest"),
          (6, "Artifact.activateLinuxEngineArtifactWithInstalledSmoke authority environment identity policy installRoot candidateRoot digest")
        ]
      rawWriterLock =
        [(1, "withEngineMaterializationLock enginesRoot action")]
      rawArtifactInternalImport =
        [(1, "import Infernix.Engines.Artifact.Internal")]
      rawLockInternalImport =
        [(1, "import Infernix.Engines.MaterializationLock.Internal")]
      rawProjectLockInternalImport =
        [(1, "import Infernix.Python.MutationLock.Internal")]
      rawDownloadCacheLockInternalImport =
        [ (1, "import Infernix.Engines.DownloadCacheLock.Internal"),
          (2, "withDownloadCacheMutationLockInternal cacheRoot action")
        ]
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            rawTransactionAccess
        )
    )
    (fail "engine worker may not invoke raw artifact transactions")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Runtime/CappedEngine/Internal.hs"
            rawWriterLock
        )
    )
    (fail "capped-engine reader may not acquire the exclusive materialization lock")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Engines/LinuxNative.hs"
            (rawArtifactInternalImport <> rawLockInternalImport)
        )
    )
    (fail "Linux materialization may not import raw writer implementations")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Engines/AppleSilicon/Internal.hs"
            rawProjectLockInternalImport
        )
    )
    (fail "Apple materialization may not import the raw project-lock implementation")
  when
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Engines/AppleSilicon/Internal.hs"
            rawDownloadCacheLockInternalImport
        )
    )
    (fail "Apple materialization may not import the raw download-cache lock implementation")
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawTransactionAccess
              )
          )
          (fail ("artifact transaction lint rejected its writer owner " <> owner))
    )
    [ "src/Infernix/Engines/Artifact/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawWriterLock
              )
          )
          (fail ("materialization-lock lint rejected its writer owner " <> owner))
    )
    [ "src/Infernix/Engines/MaterializationLock/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawArtifactInternalImport
              )
          )
          (fail ("artifact internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/Artifact.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawLockInternalImport
              )
          )
          (fail ("materialization-lock internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/Artifact/Internal.hs",
      "src/Infernix/Engines/MaterializationLock.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawProjectLockInternalImport
              )
          )
          (fail ("project-lock internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/Provisioning.hs",
      "src/Infernix/Python.hs"
    ]
  mapM_
    ( \owner ->
        unless
          ( null
              ( artifactWriterBoundaryViolations
                  owner
                  rawDownloadCacheLockInternalImport
              )
          )
          (fail ("download-cache lock internal import lint rejected its owner " <> owner))
    )
    [ "src/Infernix/Engines/DownloadCacheLock/Internal.hs",
      "src/Infernix/Engines/Provisioning.hs"
    ]
  unless
    ( null
        ( artifactWriterBoundaryViolations
            "test/artifact-transaction/Spec.hs"
            (rawTransactionAccess <> rawWriterLock)
        )
    )
    (fail "artifact writer ownership lint must stay scoped to production sources")
  unless
    ( null
        ( artifactWriterBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            [ (1, "-- installEngineArtifactRoot candidate"),
              (2, "description = \"withEngineMaterializationLock\""),
              (3, "-- import Infernix.Engines.Artifact.Internal"),
              (4, "description = \"import Infernix.Engines.MaterializationLock.Internal\""),
              (5, "-- import Infernix.Python.MutationLock.Internal"),
              (6, "description = \"withDownloadCacheMutationLockInternal\"")
            ]
        )
    )
    (fail "artifact writer lint must ignore policy tokens in comments and string literals")

assertCappedEngineBoundary :: IO ()
assertCappedEngineBoundary = do
  let workerFile = "src/Infernix/Runtime/Worker.hs"
      rawAuthority =
        [ (1, "DirectEngineCommand executable arguments workingDirectory environment"),
          (2, "runExecutableStdioEngine executable command payload")
        ]
      renderedEnvironment =
        [(1, "Subprocess.renderSubprocessEnv processEnvironment")]
      internalImport =
        [(1, "import Infernix.Runtime.CappedEngine.Internal")]
      outputCaptureImport =
        [(1, "import Infernix.Runtime.CappedEngine.OutputCapture")]
  mapM_
    ( \fixture ->
        when
          ( null
              ( cappedEngineBoundaryViolations
                  workerFile
                  fixture
              )
          )
          (fail "worker may not recover raw capped-engine process authority")
    )
    [rawAuthority, renderedEnvironment, internalImport, outputCaptureImport]
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "src/Infernix/Runtime/CappedEngine/Internal.hs"
            (rawAuthority <> renderedEnvironment <> outputCaptureImport)
        )
    )
    (fail "capped-engine ownership lint rejected its raw-process kernel")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "src/Infernix/Cluster/Subprocess.hs"
            renderedEnvironment
        )
    )
    (fail "environment-rendering lint rejected the bounded-command kernel")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "src/Infernix/Runtime/CappedEngine.hs"
            internalImport
        )
    )
    (fail "capped-engine facade may not import its hidden implementation")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            "test/unit/Spec.hs"
            (rawAuthority <> renderedEnvironment <> internalImport <> outputCaptureImport)
        )
    )
    (fail "capped-engine ownership lint must stay scoped to production sources")
  unless
    ( null
        ( cappedEngineBoundaryViolations
            workerFile
            [ (1, "-- runExecutableStdioEngine command"),
              (2, "description = \"renderSubprocessEnv DirectEngineCommand\"")
            ]
        )
    )
    (fail "capped-engine lint must ignore policy tokens in comments and string literals")

assertBoundedEngineOutput :: IO ()
assertBoundedEngineOutput = do
  let kernelFile = "src/Infernix/Runtime/CappedEngine/Internal.hs"
      unboundedReads =
        [ (1, "stdoutOutput <- hGetContents stdoutHandle"),
          (2, "stderrOutput <- ByteString.hGetContents stderrHandle"),
          (3, "stdoutOutput <- readAllText stdoutHandle")
        ]
  when
    (null (boundedEngineOutputViolations kernelFile unboundedReads))
    (fail "capped-engine output lint must reject lazy and unbounded handle reads")
  unless
    ( null
        ( boundedEngineOutputViolations
            kernelFile
            [(1, "chunk <- ByteString.hGetSome outputHandle fixedChunkBytes")]
        )
    )
    (fail "capped-engine output lint rejected fixed bounded chunk capture")
  unless
    ( null
        ( boundedEngineOutputViolations
            kernelFile
            [ (1, "-- hGetContents stdoutHandle"),
              (2, "description = \"readAllText\"")
            ]
        )
    )
    (fail "capped-engine output lint must ignore comments and string literals")
  unless
    ( null
        ( boundedEngineOutputViolations
            "test/capped-engine-observer/Spec.hs"
            unboundedReads
        )
    )
    (fail "capped-engine output lint must stay scoped to production sources")

assertLinuxNativeMaterializationBoundary :: IO ()
assertLinuxNativeMaterializationBoundary = do
  let rawPlanAccess =
        [ (1, "mapM_ materializeLinuxNativeEngineArtifactUnlocked linuxNativeEngineBuildPlan"),
          (2, "manifest <- manifestForLinuxNativeEngineArtifact root evidence artifact")
        ]
      owner = "src/Infernix/Engines/LinuxNative.hs"
  when
    ( null
        ( linuxNativeMaterializationBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            rawPlanAccess
        )
    )
    (fail "production callers may not inspect or invoke the raw Linux materialization plan")
  unless
    (null (linuxNativeMaterializationBoundaryViolations owner rawPlanAccess))
    (fail "Linux native materialization lint rejected its sole owner")
  unless
    ( null
        ( linuxNativeMaterializationBoundaryViolations
            "test/unit/Spec.hs"
            rawPlanAccess
        )
    )
    (fail "Linux native materialization lint must stay scoped to production sources")
  unless
    ( null
        ( linuxNativeMaterializationBoundaryViolations
            "src/Infernix/Runtime/Worker.hs"
            [ (1, "-- linuxNativeEngineBuildPlan"),
              (2, "description = \"manifestForLinuxNativeEngineArtifact\"")
            ]
        )
    )
    (fail "Linux native materialization lint must ignore comments and string literals")

assertAppleArtifactProvisioningBoundary :: IO ()
assertAppleArtifactProvisioningBoundary = do
  let guardedFiles =
        [ "src/Infernix/Engines/AppleSilicon.hs",
          "src/Infernix/Engines/AppleSilicon/Internal.hs",
          "src/Infernix/Engines/Artifact.hs",
          "src/Infernix/Engines/Artifact/Internal.hs",
          "src/Infernix/Engines/Provisioning.hs",
          "src/Infernix/Engines/Provisioning/Internal.hs"
        ]
  mapM_
    ( \sourceFile -> do
        assertViolation
          sourceFile
          [(1, "import System.Process qualified as Process")]
          "System.Process imports are rejected"
        assertViolation
          sourceFile
          [(1, "result <- readCreateProcessWithExitCode specification input")]
          "raw process primitives are rejected"
    )
    guardedFiles
  assertViolation
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
    [(1, "ensurePoetryProjectReady paths")]
    "the legacy unbounded Poetry helper is rejected"
  assertViolation
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
    [(1, "ensurePoetryExecutable paths")]
    "the Poetry bootstrap helper is rejected"
  assertViolation
    "src/Infernix/Engines/Provisioning.hs"
    [(1, "liftProvisioningIO arbitraryAction")]
    "a generic provisioning IO lift is rejected"
  assertViolation
    "src/Infernix/Engines/AppleSilicon/Internal.hs"
    [(1, "Subprocess.runBoundedCommand command")]
    "direct bounded-kernel use outside the provisioning facade is rejected"
  unless
    ( null
        ( appleArtifactProvisioningViolations
            "src/Infernix/Engines/Provisioning.hs"
            [(1, "Subprocess.runBoundedCommand command")]
        )
    )
    (fail "Apple artifact provisioning lint must permit its sole bounded-kernel owner")
  unless
    ( null
        ( appleArtifactProvisioningViolations
            "src/Infernix/Engines/AppleSilicon/Internal.hs"
            [ (1, "-- import System.Process"),
              (2, "description = \"readCreateProcessWithExitCode\"")
            ]
        )
    )
    (fail "Apple artifact provisioning lint must ignore policy tokens in comments and string literals")
  unless
    ( null
        ( appleArtifactProvisioningViolations
            "src/Infernix/Runtime/Daemon.hs"
            [(1, "import System.Process")]
        )
    )
    (fail "Apple artifact provisioning lint must stay scoped to the artifact boundary")

assertViolation :: FilePath -> [(Int, String)] -> String -> IO ()
assertViolation sourceFile numberedLines message =
  when
    (null (appleArtifactProvisioningViolations sourceFile numberedLines))
    (fail ("Apple artifact provisioning lint: " <> message <> " in " <> sourceFile))
