{-# LANGUAGE DataKinds #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE LinearTypes #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}

-- | Phase 1 Sprint 1.16 — the bounded-command kernel of the
-- managed-state-transition doctrine
-- ('documents/architecture/managed_state_transitions.md'). 'SubprocessEnv'
-- carries @HOME@ and @TMPDIR@ as required fields behind a hidden constructor,
-- so a subprocess spawned with an environment missing them is unrepresentable;
-- values come from the typed host manifest and the repo-local data root, never
-- from a process-inherited environment variable. 'runBoundedCommand' takes a
-- required 'Timeout' and returns a total 'CommandOutcome', so an unbounded exec
-- and a success-or-fatal collapse are both unrepresentable. The raw spawn
-- primitive is not exported.
module Infernix.Cluster.Subprocess
  ( SubprocessEnv,
    clusterSubprocessEnv,
    renderSubprocessEnv,
    Timeout (..),
    RetryPolicy (..),
    FailureClass (..),
    ClusterOperation (..),
    CommandPolicyPlan,
    CommandPolicy,
    commandPolicyTimeout,
    commandPolicyRetryPolicy,
    commandPolicyFailureClass,
    compileCommandPolicyPlan,
    commandPolicyFor,
    ClusterCommand,
    OperatorKubectlCommand,
    TestCommand (..),
    TestProtocolEvidenceCase (..),
    clusterCommandOperation,
    BoundedCommand,
    boundedCommandOperation,
    boundedOperatorKubectlOperation,
    boundedCommandLabel,
    CommandOutcome (..),
    compileBoundedCommand,
    compileOperatorKubectlCommand,
    compileTestCommand,
    ExactExecutableSnapshotTestPoint (..),
    compileExactExecutableSnapshotTestCommand,
    compileProvisioningCommand,
    compileProvisioningCommandWithExecutable,
    compileProvisioningCommandWithExecutableInMutationRoot,
    provisioningRuntimeClosureShapeForTest,
    resolveProvisioningCommandExecutable,
    resolveProvisioningPoetry,
    resolveProvisioningPython,
    resolveProvisioningHostNativeCli,
    ProvisioningMutationRoot,
    ProvisioningFilesystemMutation,
    ProvisioningFilesystemMutationOutcome (..),
    observeProvisioningMutationRoot,
    provisioningCreateDirectoryLeaf,
    provisioningCreateSymbolicLinkLeaf,
    provisioningRemoveTreeLeaf,
    provisioningRenameSiblingDirectory,
    provisioningRenameSiblingRegularFile,
    provisioningReplaceSiblingRegularFile,
    runProvisioningFilesystemMutation,
    safeProvisioningMutationLinkTargetForTest,
    safeRelativeOperandForTest,
    NativeArtifactCachePlan,
    nativeArtifactCachePlan,
    NativeArtifactInvocationPlan,
    nativeArtifactInvocationPlan,
    NativeArtifactCommandOutcome (..),
    NativeArtifactOutputStream (..),
    runClosedInstalledRunnerSmoke,
    runClosedInstalledPythonSourceIsolationSmoke,
    runClosedLinuxNativeArtifactSmoke,
    ProvisioningContractObservation (..),
    provisioningContractForTest,
    -- Sprint 1.20 Apple-cohort regression surfaces. Each names a defect the
    -- machine-independent gates could not reach and the first Apple cohort
    -- attempt found live.
    DyldAuditLine (..),
    parseDyldAuditLineForTest,
    installedRunnerApplicationOutputForTest,
    ElfAuditLine (..),
    SealedRunLoaderAudit (..),
    parseElfAuditLineForTest,
    sealedLinuxRunnerApplicationOutputForTest,
    sealedRunLoaderAuditForTest,
    sealedArtifactRuntimeEnvironmentForTest,
    renderedEnvironmentContractForTest,
    linuxSealedRunRenderedEnvironmentForTest,
    darwinPythonSnapshotTargetEnvironmentForTest,
    darwinPythonSnapshotClosureEnvironmentContractForTest,
    sealedPackageClosureContentDisagreementForTest,
    retainedPackageClosureExcludesFileForTest,
    sealedPackageClosureExcludesFileForTest,
    retainedPackageClosureExcludesLinkForTest,
    sealedPackageClosureExcludesLinkForTest,
    supervisorTargetEnvironmentContractForTest,
    runBoundedCommand,
    dispatchInternalSubprocessMode,
    BoundedCommandActivitiesQuiescent,
    boundedCommandActivitiesOwnerProcessGroup,
    proveBoundedCommandActivitiesQuiescent,
    AbandonedActivitiesRecovered,
    recoverAbandonedBoundedCommandActivities,
    -- Sprint 1.20 process-group lifecycle regression surfaces. An exact leader
    -- that is absent over a live group is the ordinary reap race, not a pid
    -- reuse, and both classifications used to conflate the two. These drive the
    -- corrected paths against a real group without handing the caller a
    -- constructor for 'ActivityProcessIdentity'.
    signalActivityProcessGroupForTest,
    observeRecoverableProcessGroupActiveForTest,
  )
where

import Control.Concurrent (forkIO, killThread, rtsSupportsBoundThreads, yield)
import Control.Concurrent.MVar
  ( MVar,
    modifyMVar,
    modifyMVar_,
    newEmptyMVar,
    newMVar,
    putMVar,
    readMVar,
    takeMVar,
    tryPutMVar,
    tryTakeMVar,
  )
import Control.Exception
  ( Exception,
    IOException,
    SomeAsyncException,
    SomeException,
    displayException,
    finally,
    fromException,
    mask,
    mask_,
    throwIO,
    toException,
    try,
  )
import Control.Monad
  ( filterM,
    foldM,
    forever,
    guard,
    unless,
    void,
    when,
    zipWithM,
  )
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson qualified as Aeson
import Data.Aeson.Key (Key)
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.Types (Object, Pair, Parser)
import Data.Bits ((.&.), (.|.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Base64 qualified as Base64
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isDigit, isHexDigit, isSpace, toLower)
import Data.IORef (IORef, atomicModifyIORef', newIORef)
import Data.List qualified as List
import Data.Maybe (catMaybes, fromMaybe, isJust, isNothing, listToMaybe, mapMaybe)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Word (Word64)
import GHC.Clock (getMonotonicTimeNSec)
import GHC.Conc (threadWaitRead, threadWaitWrite)
import GHC.IO.Exception (IOErrorType (EOF, Interrupted, ResourceExhausted))
import Infernix.Cluster.Command
  ( ClusterCommand,
    ClusterOperation (..),
    OperatorKubectlCommand,
    clusterCommandOperation,
  )
import Infernix.Cluster.Command qualified as Command
import Infernix.Cluster.Subprocess.Activity qualified as Activity
import Infernix.Cluster.Subprocess.Protocol qualified as Protocol
import Infernix.Config (Paths (..))
import Infernix.DescriptorSpace (requireBoundedDescriptorSpace)
import Infernix.Engines.Artifact qualified as Artifact
import Infernix.Engines.Artifact.Identity qualified as ArtifactIdentity
import Infernix.Engines.Artifact.Target qualified as ArtifactTarget
import Infernix.Engines.MaterializationLock
  ( ArtifactGenerationLease,
    artifactGenerationLease,
    artifactGenerationLeaseFields,
    withTryArtifactGenerationReadLock,
  )
import Infernix.Engines.Provisioning.Internal qualified as Provisioning
import Infernix.Error
  ( finallyPreservingPrimary,
    onExceptionPreservingPrimary,
    runCleanupsPreservingFailures,
  )
import Infernix.Evidence.Readiness qualified as Readiness
import Infernix.HostConfig qualified as HostConfig
import Infernix.HostTools qualified as HostTools
import Infernix.ProcessIdentity
  ( ProcessBirthIdentity (..),
    dropInheritedProcessIdentity,
    parseProcessBirthIdentity,
    readProcessBirthIdentity,
    registerCurrentProcessIdentity,
    renderProcessBirthIdentity,
  )
import Infernix.ProcessIdentity.Internal qualified as ProcessIdentityInternal
import Infernix.Types (RuntimeMode)
import Numeric (readHex, showHex)
import Numeric.Natural (Natural)
import System.Directory
  ( Permissions (executable),
    canonicalizePath,
    createDirectory,
    createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    getPermissions,
    listDirectory,
    removeDirectory,
    removeFile,
    removePathForcibly,
    renameDirectory,
    setCurrentDirectory,
  )
import System.Environment (getArgs, getExecutablePath)
import System.Exit (ExitCode (..))
import System.FilePath
  ( dropTrailingPathSeparator,
    isAbsolute,
    joinPath,
    makeRelative,
    normalise,
    splitDirectories,
    splitSearchPath,
    takeDirectory,
    takeFileName,
    (</>),
  )
import System.IO
  ( BufferMode (NoBuffering),
    Handle,
    SeekMode (AbsoluteSeek),
    hClose,
    hFlush,
    hSetBinaryMode,
    hSetBuffering,
    stderr,
    stdin,
    stdout,
  )
import System.IO.Error (ioeGetErrorType, isAlreadyExistsError, isDoesNotExistError, isPermissionError)
import System.Info qualified as SystemInfo
import System.Posix.Directory
  ( closeDirStream,
    readDirStream,
  )
import System.Posix.Directory qualified as PosixDirectory
import System.Posix.Directory.Fd
  ( unsafeOpenDirStreamFd,
  )
import System.Posix.Files
  ( FileStatus,
    createNamedPipe,
    createSymbolicLink,
    fileMode,
    getFdStatus,
    getSymbolicLinkStatus,
    groupWriteMode,
    isDirectory,
    isRegularFile,
    isSymbolicLink,
    otherWriteMode,
    ownerExecuteMode,
    ownerModes,
    ownerReadMode,
    ownerWriteMode,
    readSymbolicLink,
    setFileMode,
  )
import System.Posix.Files qualified as PosixFiles
import System.Posix.IO
  ( FdOption (CloseOnExec, NonBlockingRead),
    OpenFileFlags (cloexec, creat, directory, exclusive, nofollow, nonBlock),
    OpenMode (ReadOnly, ReadWrite, WriteOnly),
    closeFd,
    createPipe,
    defaultFileFlags,
    dup,
    dupTo,
    fdSeek,
    openFd,
    openFdAt,
    setFdOption,
    stdError,
    stdInput,
    stdOutput,
  )
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Process
  ( ProcessStatus (..),
    executeFile,
    exitImmediately,
    forkProcess,
    getProcessGroupID,
    getProcessGroupIDOf,
    getProcessID,
    getProcessStatus,
    setProcessGroupIDOf,
  )
import System.Posix.Signals
  ( Handler (CatchOnce),
    Signal,
    awaitSignal,
    installHandler,
    nullSignal,
    sigCONT,
    sigKILL,
    sigSTOP,
    sigTERM,
    signalProcess,
    signalProcessGroup,
  )
import System.Posix.Types (Fd (..), FileMode, ProcessID)
import System.Posix.Unistd (fileSynchronise)
import System.Process
  ( CreateProcess (..),
    ProcessHandle,
    StdStream (CreatePipe),
    createProcess,
    getPid,
    getProcessExitCode,
    proc,
    waitForProcess,
  )
import System.Timeout (timeout)
import Text.Read (readMaybe)

-- | A total process environment. The constructor is hidden and
-- 'clusterSubprocessEnv' is the sole builder, so @HOME@ and @TMPDIR@ are
-- always present.
data SubprocessEnv = SubprocessEnv
  { subprocessEnvSearchPath :: !FilePath,
    subprocessEnvHome :: !FilePath,
    subprocessEnvTmpdir :: !FilePath,
    subprocessEnvLang :: !String,
    subprocessEnvRepoRoot :: !FilePath,
    subprocessEnvRuntimeRoot :: !FilePath,
    subprocessEnvHelmConfigHome :: !FilePath,
    subprocessEnvHelmCacheHome :: !FilePath,
    subprocessEnvHelmDataHome :: !FilePath,
    subprocessEnvCommandPolicyPlan :: !CommandPolicyPlan,
    subprocessEnvHostConfig :: !HostConfig.HostConfig,
    subprocessEnvAvailableTools :: ![HostTools.HostTool]
  }

-- | Build the environment for host subprocesses from the typed host
-- manifest and the repo-local data root. Fails closed when the manifest is
-- absent rather than falling back to an ambient environment.
clusterSubprocessEnv :: Paths -> IO SubprocessEnv
clusterSubprocessEnv paths =
  case pathsHostConfig paths of
    Nothing -> missingManifestError "clusterSubprocessEnv"
    Just config -> clusterSubprocessEnvWithSearchPath paths (searchPathForHost config)

-- | Build the subprocess environment with a caller-supplied @PATH@ (for callers
-- that assemble their own tool-directory search path) while still requiring
-- @HOME@ and @TMPDIR@ from the typed host manifest and the repo-local data root.
-- Fails closed when the manifest is absent rather than falling back to an
-- ambient environment, so a subprocess spawned without @HOME@/@TMPDIR@ is
-- unrepresentable.
clusterSubprocessEnvWithSearchPath :: Paths -> FilePath -> IO SubprocessEnv
clusterSubprocessEnvWithSearchPath paths searchPath =
  case pathsHostConfig paths of
    Nothing -> missingManifestError "clusterSubprocessEnvWithSearchPath"
    Just config -> do
      let home =
            Text.unpack (HostConfig.hostHomeDirectory (HostConfig.hostFilesystem config))
          tmpdir = dataRoot paths </> "tmp"
          kernelPaths =
            [ ("repository root", repoRoot paths),
              ("HOME", home),
              ("TMPDIR", tmpdir),
              ("HELM_CONFIG_HOME", helmConfigRoot paths),
              ("HELM_CACHE_HOME", helmCacheRoot paths),
              ("HELM_DATA_HOME", helmDataRoot paths)
            ]
      mapM_ validateKernelPath kernelPaths
      policyPlan <-
        either
          (ioError . userError . ("invalid generated host command policies: " <>))
          pure
          (compileCommandPolicyPlan (HostConfig.hostCommandPolicies config))
      validateConfiguredToolSearchPathDirectories config
      mapM_ validateSearchPathComponent (splitSearchPath searchPath)
      availableTools <-
        filterM
          (configuredToolAvailable config)
          [minBound .. maxBound]
      shimRoot <- materializeCommandShims paths config availableTools
      validateSearchPathComponent shimRoot
      let pinnedSearchPath =
            List.intercalate
              ":"
              (shimRoot : [searchPath | not (null searchPath)])
      mapM_
        (createDirectoryIfMissing True)
        [ tmpdir,
          helmConfigRoot paths,
          helmCacheRoot paths,
          helmDataRoot paths
        ]
      pure
        SubprocessEnv
          { subprocessEnvSearchPath = pinnedSearchPath,
            subprocessEnvHome = home,
            subprocessEnvTmpdir = tmpdir,
            subprocessEnvLang = "C.UTF-8",
            subprocessEnvRepoRoot = repoRoot paths,
            subprocessEnvRuntimeRoot = runtimeRoot paths,
            subprocessEnvHelmConfigHome = helmConfigRoot paths,
            subprocessEnvHelmCacheHome = helmCacheRoot paths,
            subprocessEnvHelmDataHome = helmDataRoot paths,
            subprocessEnvCommandPolicyPlan = policyPlan,
            subprocessEnvHostConfig = config,
            subprocessEnvAvailableTools = availableTools
          }

configuredToolAvailable :: HostConfig.HostConfig -> HostTools.HostTool -> IO Bool
configuredToolAvailable config tool = do
  let configuredPath = configuredToolPath config tool
  if null configuredPath || not (isAbsolute configuredPath)
    then pure False
    else do
      availability <-
        ( try $ do
            fileExists <- doesFileExist configuredPath
            if fileExists
              then executable <$> getPermissions configuredPath
              else pure False
        ) ::
          IO (Either IOException Bool)
      pure $
        case availability of
          Left _ -> False
          Right isAvailable -> isAvailable

materializeCommandShims ::
  Paths ->
  HostConfig.HostConfig ->
  [HostTools.HostTool] ->
  IO FilePath
materializeCommandShims paths config availableTools = do
  let generationDigest = commandShimGeneration config availableTools
      shimParent = runtimeRoot paths </> "command-shims"
  validateSearchPathComponent shimParent
  createDirectoryIfMissing True shimParent
  setFileMode shimParent ownerModes
  -- Establish this process's birth identity before reclaiming, so the sweep
  -- can positively identify this process's own root and leave it alone
  -- instead of relying on an unreadable identity failing closed.
  processId <- getProcessID
  processIdentity <- registerCurrentProcessIdentity
  cleanupDeadCommandShimStagingDirectories shimParent
  let ownerId = show processId
      identityDigest = commandShimProcessIdentityDigest processIdentity
      generationRoot =
        shimParent
          </> ( commandShimOwnedLeafPrefix
                  <> ownerId
                  <> "-"
                  <> identityDigest
                  <> "-"
                  <> generationDigest
              )
  generationValid <-
    verifyCommandShimGeneration generationRoot config availableTools
  if generationValid
    then pure generationRoot
    else do
      stagingRoot <-
        createCommandShimStagingRoot
          shimParent
          commandShimStagingLeafPrefix
          ownerId
          identityDigest
          0
      setFileMode stagingRoot ownerModes
      mapM_ (materializeShim stagingRoot) availableTools
      materializeGenerationMarker stagingRoot generationDigest
      publishCommandShimGeneration
        shimParent
        ownerId
        identityDigest
        generationRoot
        stagingRoot
        1
  where
    -- Move staging into the owned generation root. POSIX @rename(2)@ cannot
    -- replace a non-empty directory, so a root that already exists and fails
    -- verification cannot be recovered by renaming over it: every attempt
    -- fails with @ENOTEMPTY@, and with it every external command this process
    -- would run. One bounded supersede-and-retry vacates such a root in a
    -- single atomic step, so the root is never observed half-built.
    publishCommandShimGeneration ::
      FilePath ->
      String ->
      String ->
      FilePath ->
      FilePath ->
      Int ->
      IO FilePath
    publishCommandShimGeneration
      shimParent
      ownerId
      identityDigest
      generationRoot
      stagingRoot
      supersedesRemaining = do
        publishResult <-
          try (renameDirectory stagingRoot generationRoot) ::
            IO (Either IOException ())
        case publishResult of
          Right () -> verifyPublishedGeneration generationRoot
          Left publishError -> do
            concurrentlyPublished <-
              verifyCommandShimGeneration generationRoot config availableTools
            if concurrentlyPublished
              then do
                cleanupCommandShimStagingDirectory stagingRoot
                pure generationRoot
              else
                if supersedesRemaining <= 0
                  then do
                    cleanupCommandShimStagingDirectory stagingRoot
                    ioError publishError
                  else do
                    vacateCommandShimGenerationRoot
                      shimParent
                      ownerId
                      identityDigest
                      generationRoot
                    publishCommandShimGeneration
                      shimParent
                      ownerId
                      identityDigest
                      generationRoot
                      stagingRoot
                      (supersedesRemaining - 1)

    materializeShim shimRoot tool = do
      let shimPath =
            shimRoot
              </> Text.unpack (HostTools.hostToolName tool)
          configuredPath = configuredToolPath config tool
      createSymbolicLink configuredPath shimPath

    materializeGenerationMarker shimRoot generationDigest = do
      let markerPath = shimRoot </> commandShimGenerationMarker
      ByteString8.writeFile
        markerPath
        (ByteString8.pack (generationDigest <> "\n"))
      setFileMode markerPath ownerReadMode

    verifyPublishedGeneration generationRoot = do
      published <-
        verifyCommandShimGeneration generationRoot config availableTools
      if published
        then pure generationRoot
        else
          ioError
            ( userError
                ( "published command shim generation failed verification: "
                    <> generationRoot
                )
            )

-- | Leaf prefix of a published, owner-scoped shim root. The leaf names the
-- process that minted it (pid plus process-birth-identity digest) as well as
-- the generation digest, so a root is reclaimable evidence rather than shared
-- state: 'cleanupDeadCommandShimStagingDirectories' can prove the owner is
-- gone before removing it. A shared, content-addressed name carried no owner,
-- so nothing could prove that no live process was still resolving through it,
-- and published generations therefore accumulated forever.
commandShimOwnedLeafPrefix :: FilePath
commandShimOwnedLeafPrefix = "own-"

-- | Leaf prefix of an in-progress shim root, before its atomic publication.
commandShimStagingLeafPrefix :: FilePath
commandShimStagingLeafPrefix = ".incoming-"

-- | Leaf prefix of a generation root that failed verification and was moved
-- aside so a correct one could take its name. See
-- 'vacateCommandShimGenerationRoot'.
commandShimSupersededLeafPrefix :: FilePath
commandShimSupersededLeafPrefix = ".superseded-"

-- | Atomically vacate a generation root that exists but fails verification.
--
-- POSIX @rename(2)@ fails with @ENOTEMPTY@ against a non-empty destination
-- directory, so a corrupt root cannot be replaced by renaming over it. Left
-- alone it is terminal: verification keeps failing, republication keeps
-- failing, and every external command fails with it. Reserving a sibling leaf
-- and renaming the corrupt tree into it frees the name in one atomic step,
-- with no window in which the root exists half-built.
--
-- Failures are deliberately swallowed. This runs only on a path that has
-- already failed, and the caller's retry surfaces the original publication
-- error if the name is still not free.
vacateCommandShimGenerationRoot ::
  FilePath ->
  String ->
  String ->
  FilePath ->
  IO ()
vacateCommandShimGenerationRoot shimParent ownerId identityDigest generationRoot = do
  reservation <-
    try
      ( createCommandShimStagingRoot
          shimParent
          commandShimSupersededLeafPrefix
          ownerId
          identityDigest
          0
      ) ::
      IO (Either IOException FilePath)
  case reservation of
    Left _ -> pure ()
    Right asideRoot -> do
      -- The reservation is an empty directory, and @rename(2)@ does replace an
      -- empty destination, so this move needs no separate collision handling.
      _ <-
        try (renameDirectory generationRoot asideRoot) ::
          IO (Either IOException ())
      cleanupCommandShimStagingDirectory asideRoot

commandShimGeneration ::
  HostConfig.HostConfig ->
  [HostTools.HostTool] ->
  String
commandShimGeneration config availableTools =
  ByteString8.unpack
    ( Base16.encode
        ( SHA256.hashlazy
            ( Aeson.encode
                ( Text.pack "infernix-command-shims-v1",
                  [ ( HostTools.hostToolName tool,
                      Text.pack (configuredToolPath config tool)
                    )
                  | tool <- availableTools
                  ]
                )
            )
        )
    )

createCommandShimStagingRoot ::
  FilePath ->
  FilePath ->
  String ->
  String ->
  Int ->
  IO FilePath
createCommandShimStagingRoot shimParent leafPrefix processId processIdentity candidateIndex = do
  let candidate =
        shimParent
          </> ( leafPrefix
                  <> processId
                  <> "-"
                  <> processIdentity
                  <> "-"
                  <> show candidateIndex
              )
  createResult <-
    try (createDirectory candidate) ::
      IO (Either IOException ())
  case createResult of
    Right () -> pure candidate
    Left err
      | isAlreadyExistsError err ->
          createCommandShimStagingRoot
            shimParent
            leafPrefix
            processId
            processIdentity
            (candidateIndex + 1)
      | otherwise -> ioError err

verifyCommandShimGeneration ::
  FilePath ->
  HostConfig.HostConfig ->
  [HostTools.HostTool] ->
  IO Bool
verifyCommandShimGeneration generationRoot config availableTools = do
  verification <-
    ( try $ do
        generationExists <- doesDirectoryExist generationRoot
        if not generationExists
          then pure False
          else do
            rootStatus <- getSymbolicLinkStatus generationRoot
            actualEntries <- List.sort <$> listDirectory generationRoot
            let expectedEntries =
                  List.sort
                    ( commandShimGenerationMarker
                        : [ Text.unpack (HostTools.hostToolName tool)
                          | tool <- availableTools
                          ]
                    )
                -- 'rootStatus' comes from 'getSymbolicLinkStatus' (an lstat),
                -- so this rejects a symlink standing in for the root. The
                -- root's write bits are deliberately not asserted: the entry
                -- set, link targets, and marker digest below detect actual
                -- mutation, whereas a mode check only detected the
                -- possibility of it -- and at a single uid it stopped no
                -- adversary (this module chmods a shim root itself in
                -- 'cleanupCommandShimStagingDirectory'), while making a
                -- published root unremovable by ordinary tooling.
                structuralRoot = isDirectory rootStatus
            linksMatch <-
              and
                <$> mapM
                  (configuredShimMatches generationRoot config)
                  availableTools
            markerMatches <-
              commandShimGenerationMarkerMatches
                generationRoot
                (commandShimGeneration config availableTools)
            pure
              ( structuralRoot
                  && actualEntries == expectedEntries
                  && linksMatch
                  && markerMatches
              )
    ) ::
      IO (Either IOException Bool)
  pure $
    case verification of
      Left _ -> False
      Right valid -> valid

commandShimGenerationMarker :: FilePath
commandShimGenerationMarker = ".generation"

commandShimGenerationMarkerMatches :: FilePath -> String -> IO Bool
commandShimGenerationMarkerMatches generationRoot expectedDigest = do
  let markerPath = generationRoot </> commandShimGenerationMarker
  markerStatus <- getSymbolicLinkStatus markerPath
  if not (isRegularFile markerStatus)
    then pure False
    else do
      markerContents <- ByteString8.readFile markerPath
      let writeModes =
            ownerWriteMode .|. groupWriteMode .|. otherWriteMode
      pure
        ( fileMode markerStatus .&. writeModes == 0
            && markerContents
              == ByteString8.pack (expectedDigest <> "\n")
        )

configuredShimMatches ::
  FilePath ->
  HostConfig.HostConfig ->
  HostTools.HostTool ->
  IO Bool
configuredShimMatches generationRoot config tool = do
  let shimPath =
        generationRoot
          </> Text.unpack (HostTools.hostToolName tool)
  shimStatus <- getSymbolicLinkStatus shimPath
  shimTarget <- readSymbolicLink shimPath
  pure
    ( isSymbolicLink shimStatus
        && shimTarget == configuredToolPath config tool
    )

-- | Reclaim every shim root whose owning process is provably gone -- staging
-- left by a crash mid-publication, a superseded root, and published
-- owner-scoped roots alike. This is what bounds @command-shims@: each live
-- process holds at most one root per generation digest, and a root outlives
-- its owner only until the next materialization sweeps it.
--
-- Reclamation is fail-closed. A live pid whose birth identity cannot be read
-- is left alone, because it cannot be distinguished from a live owner. On
-- Darwin that identity comes from the process registry, which knows only
-- infernix processes, so a root whose owner was @SIGKILL@ed and whose pid was
-- later recycled by an unrelated process is not reclaimed here. That residue
-- is bounded and benign: an owner-scoped root is @0700@, so ordinary tooling
-- (@git clean@, @rm -rf@) removes it, which is exactly what a mode-@0500@
-- root denied.
cleanupDeadCommandShimStagingDirectories :: FilePath -> IO ()
cleanupDeadCommandShimStagingDirectories shimParent = do
  entries <- listDirectory shimParent
  mapM_ cleanupIfDead entries
  where
    cleanupIfDead entry =
      case commandShimStagingOwner entry of
        Nothing -> pure ()
        Just (processId, recordedIdentity) -> do
          ownerAlive <- processIsAlive processId
          if ownerAlive
            then do
              currentIdentity <- readProcessBirthIdentity processId
              case currentIdentity of
                Just identity
                  | commandShimProcessIdentityDigest identity
                      /= recordedIdentity ->
                      cleanupOwnedStagingDirectory entry
                _ -> pure ()
            else do
              cleanupOwnedStagingDirectory entry

    cleanupOwnedStagingDirectory entry = do
      let stagingRoot = shimParent </> entry
      statusResult <-
        try (getSymbolicLinkStatus stagingRoot) ::
          IO (Either IOException FileStatus)
      case statusResult of
        Right status
          | isDirectory status ->
              cleanupCommandShimStagingDirectory stagingRoot
        _ -> pure ()

-- | The leaf prefixes whose directories name an owning process and are
-- therefore reclaimable once that owner is proven gone: in-progress staging,
-- a superseded root awaiting removal, and a published owner-scoped root.
commandShimReclaimableLeafPrefixes :: [FilePath]
commandShimReclaimableLeafPrefixes =
  [ commandShimStagingLeafPrefix,
    commandShimSupersededLeafPrefix,
    commandShimOwnedLeafPrefix
  ]

-- | Parse the owning pid and process-birth-identity digest out of a
-- reclaimable shim leaf. The trailing component is a candidate index for
-- staging and superseded leaves and a generation digest for published ones,
-- so both shapes are accepted.
commandShimStagingOwner :: FilePath -> Maybe (Integer, String)
commandShimStagingOwner entry = do
  suffix <-
    listToMaybe
      (mapMaybe (`List.stripPrefix` entry) commandShimReclaimableLeafPrefixes)
  let (processIdText, identitySuffix) = span isDigit suffix
  processId <- readMaybe processIdText
  identityAndTrailer <-
    case identitySuffix of
      '-' : value -> Just value
      _ -> Nothing
  let (identityDigest, trailerSuffix) = splitAt 64 identityAndTrailer
  guard
    ( processId > 0
        && processId <= 2147483647
        && length identityDigest == 64
        && all isHexDigit identityDigest
        && case trailerSuffix of
          '-' : trailer -> commandShimLeafTrailerValid trailer
          _ -> False
    )
  pure (processId, identityDigest)

-- | A reclaimable leaf's trailing component: a decimal candidate index, or a
-- 64-character hex generation digest.
commandShimLeafTrailerValid :: String -> Bool
commandShimLeafTrailerValid trailer =
  not (null trailer)
    && ( all isDigit trailer
           || (length trailer == 64 && all isHexDigit trailer)
       )

commandShimProcessIdentityDigest :: ProcessBirthIdentity -> String
commandShimProcessIdentityDigest =
  ByteString8.unpack
    . Base16.encode
    . SHA256.hash
    . ByteString8.pack
    . renderProcessBirthIdentity

processIsAlive :: Integer -> IO Bool
processIsAlive processId = do
  probe <-
    try (signalProcess nullSignal (fromIntegral processId)) ::
      IO (Either IOException ())
  pure $
    case probe of
      Right () -> True
      Left err -> isPermissionError err

cleanupCommandShimStagingDirectory :: FilePath -> IO ()
cleanupCommandShimStagingDirectory stagingRoot = do
  setFileMode stagingRoot ownerModes
  removePathForcibly stagingRoot

validateConfiguredToolSearchPathDirectories :: HostConfig.HostConfig -> IO ()
validateConfiguredToolSearchPathDirectories config =
  mapM_ validateConfiguredToolDirectory [minBound .. maxBound]
  where
    validateConfiguredToolDirectory tool =
      let configuredPath = configuredToolPath config tool
       in if null configuredPath || not (isAbsolute configuredPath)
            then pure ()
            else validateSearchPathComponent (takeDirectory configuredPath)

validateSearchPathComponent :: FilePath -> IO ()
validateSearchPathComponent component
  | null component =
      ioError (userError "subprocess PATH components must be non-empty")
  | not (isAbsolute component) =
      ioError
        (userError ("subprocess PATH component must be absolute: " <> component))
  | ':' `elem` component =
      ioError
        ( userError
            ("subprocess PATH component must not contain ':': " <> component)
        )
  | otherwise = pure ()

validateKernelPath :: (String, FilePath) -> IO ()
validateKernelPath (label, path)
  | null path =
      ioError (userError ("subprocess " <> label <> " must be non-empty"))
  | not (isAbsolute path) =
      ioError
        ( userError
            ("subprocess " <> label <> " must be absolute: " <> path)
        )
  | otherwise = pure ()

missingManifestError :: String -> IO a
missingManifestError caller =
  ioError
    ( userError
        ( caller
            <> ": host manifest is unavailable; run `infernix init` to stage "
            <> "./infernix-host.dhall before invoking external commands"
        )
    )

-- | Compose @PATH@ from the parent directories of the manifest's tool paths
-- plus the fixed fallback system directories, deduplicated in order.
searchPathForHost :: HostConfig.HostConfig -> FilePath
searchPathForHost config =
  List.intercalate ":" (List.nub (toolDirs <> fallbackDirs))
  where
    toolPaths = HostConfig.hostToolPaths config
    configuredPaths =
      map
        Text.unpack
        [ HostConfig.hostDocker toolPaths,
          HostConfig.hostKubectl toolPaths,
          HostConfig.hostHelm toolPaths,
          HostConfig.hostKind toolPaths,
          HostConfig.hostCabal toolPaths,
          HostConfig.hostGhc toolPaths,
          HostConfig.hostNpm toolPaths,
          HostConfig.hostNode toolPaths,
          HostConfig.hostPython3 toolPaths,
          HostConfig.hostPython311 toolPaths,
          HostConfig.hostLlamaCli toolPaths,
          HostConfig.hostWhisperCli toolPaths,
          HostConfig.hostPoetry toolPaths,
          HostConfig.hostGit toolPaths,
          HostConfig.hostTar toolPaths,
          HostConfig.hostCurl toolPaths
        ]
    toolDirs =
      [ takeDirectory configuredPath
      | configuredPath <- configuredPaths,
        not (null configuredPath),
        isAbsolute configuredPath
      ]
    fallbackDirs =
      [ "/usr/local/sbin",
        "/usr/local/bin",
        "/usr/sbin",
        "/usr/bin",
        "/sbin",
        "/bin"
      ]

-- | Render the kernel-owned environment for a spawn. Home, temporary, and Helm
-- state paths are always present because 'SubprocessEnv' cannot be built
-- without validated absolute values for them.
renderSubprocessEnv :: SubprocessEnv -> [(String, String)]
renderSubprocessEnv environment =
  [ ("PATH", subprocessEnvSearchPath environment),
    ("HOME", subprocessEnvHome environment),
    ("TMPDIR", subprocessEnvTmpdir environment),
    ("LANG", subprocessEnvLang environment),
    ("LC_ALL", subprocessEnvLang environment),
    ("HELM_CONFIG_HOME", subprocessEnvHelmConfigHome environment),
    ("HELM_CACHE_HOME", subprocessEnvHelmCacheHome environment),
    ("HELM_DATA_HOME", subprocessEnvHelmDataHome environment)
  ]

-- | A required wall-clock bound for a subprocess, in microseconds.
newtype Timeout = Timeout {timeoutMicros :: Int}
  deriving (Eq, Show)

-- | Exact descriptor-observed authority for one provisioning mutation root.
-- The constructor is hidden; callers cannot invent the device/inode tuple sent
-- to the isolated mutation target.
data ProvisioningMutationRoot = ProvisioningMutationRoot
  { provisioningMutationRootPath :: !FilePath,
    provisioningMutationRootDeviceId :: !Integer,
    provisioningMutationRootFileId :: !Integer,
    provisioningMutationRootMode :: !Integer
  }
  deriving (Eq, Show)

data ProvisioningFilesystemMutation
  = ProvisioningCreateDirectoryLeaf
      !ProvisioningMutationRoot
      ![FilePath]
      !FilePath
  | ProvisioningRemoveTreeLeaf
      !ProvisioningMutationRoot
      ![FilePath]
      !FilePath
  | ProvisioningRenameSiblingDirectory
      !ProvisioningMutationRoot
      ![FilePath]
      !FilePath
      !FilePath
  | ProvisioningRenameSiblingRegularFile
      !ProvisioningMutationRoot
      ![FilePath]
      !FilePath
      !FilePath
  | -- | Atomically rename one regular file over an existing regular-file
    -- sibling.
    --
    -- 'ProvisioningRenameSiblingRegularFile' refuses an existing destination,
    -- which is the right precondition for a first publication. A durable
    -- record's /replacement/ needs the opposite: the destination must already
    -- be a regular file and must be replaced in one step, so that a crash
    -- leaves either the previous record or the new one and never neither.
    -- Splitting it into unlink-then-rename would open exactly that window.
    ProvisioningReplaceSiblingRegularFile
      !ProvisioningMutationRoot
      ![FilePath]
      !FilePath
      !FilePath
  | -- | Create one symbolic link at a single safe leaf under a retained parent.
    --
    -- @unix-2.8.8.0@ exposes no public @symlinkat@ and @foreign import@ is
    -- forbidden throughout repo-owned Haskell, so a descriptor-anchored
    -- symbolic link can only be created by this kernel, which @fchdir@s into
    -- the retained parent and then names one CWD-relative leaf.
    ProvisioningCreateSymbolicLinkLeaf
      !ProvisioningMutationRoot
      ![FilePath]
      !FilePath
      !FilePath
  deriving (Eq, Show)

data ProvisioningMutationWorkingDirectory
  = ProvisioningMutationWorkingDirectory
      !ProvisioningMutationRoot
      ![FilePath]
      !(Maybe FilePath)
  deriving (Eq, Show)

data ProvisioningFilesystemMutationOutcome
  = ProvisioningMutationSucceeded
  | ProvisioningMutationRejectedSpec !Text.Text
  | ProvisioningMutationKernelFailure !Text.Text
  | ProvisioningMutationTimedOut !Timeout
  deriving (Eq, Show)

data ProvisioningMutationHelperOutcome
  = ProvisioningMutationHelperSucceeded
  | ProvisioningMutationHelperRejected !Text.Text
  | ProvisioningMutationHelperKernelFailure !Text.Text
  deriving (Eq, Show)

observeProvisioningMutationRoot ::
  FilePath ->
  IO
    ( Either
        ProvisioningFilesystemMutationOutcome
        ProvisioningMutationRoot
    )
observeProvisioningMutationRoot rootPath
  | not (validProvisioningMutationRootPath rootPath) =
      pure
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation root must be an absolute normalized path"
            )
        )
  | otherwise = do
      observed <-
        try @IOException $ mask $ \restore -> do
          listedStatus <- getSymbolicLinkStatus rootPath
          if not (isDirectory listedStatus && not (isSymbolicLink listedStatus))
            then pure (Left "provisioning mutation root is not a real directory")
            else do
              descriptor <-
                restore
                  ( openFd
                      rootPath
                      ReadOnly
                      defaultFileFlags
                        { nofollow = True,
                          directory = True,
                          cloexec = True
                        }
                  )
              finallyPreservingPrimary
                ( do
                    openedStatus <- getFdStatus descriptor
                    finalStatus <- getSymbolicLinkStatus rootPath
                    pure
                      ( if exactMutationDirectoryStatus listedStatus openedStatus
                          && exactMutationDirectoryStatus openedStatus finalStatus
                          && not (isSymbolicLink finalStatus)
                          then
                            Right
                              ProvisioningMutationRoot
                                { provisioningMutationRootPath = rootPath,
                                  provisioningMutationRootDeviceId =
                                    fromIntegral (PosixFiles.deviceID openedStatus),
                                  provisioningMutationRootFileId =
                                    fromIntegral (PosixFiles.fileID openedStatus),
                                  provisioningMutationRootMode =
                                    fromIntegral (fileMode openedStatus)
                                }
                          else
                            Left
                              "provisioning mutation root changed during observation"
                      )
                )
                (ignoreIOException (closeFd descriptor))
      pure (classifyObservedProvisioningMutationRoot observed)

-- | Fold one mutation-root observation into its typed outcome.
classifyObservedProvisioningMutationRoot ::
  Either IOException (Either Text.Text ProvisioningMutationRoot) ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningMutationRoot
classifyObservedProvisioningMutationRoot observed =
  case observed of
    Left failure ->
      Left
        ( ProvisioningMutationKernelFailure
            (Text.pack (displayException failure))
        )
    Right (Left rejection) ->
      Left (ProvisioningMutationRejectedSpec rejection)
    Right (Right root) -> Right root

provisioningCreateDirectoryLeaf ::
  ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningCreateDirectoryLeaf root parentComponents leaf = do
  validateProvisioningMutationRelativePath parentComponents leaf
  pure
    (ProvisioningCreateDirectoryLeaf root parentComponents leaf)

provisioningRemoveTreeLeaf ::
  ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningRemoveTreeLeaf root parentComponents leaf = do
  validateProvisioningMutationRelativePath parentComponents leaf
  pure
    (ProvisioningRemoveTreeLeaf root parentComponents leaf)

-- | Create one symbolic link named by a single safe leaf under the retained
-- parent that @parentComponents@ locates within @root@.
--
-- The target is held to the same containment rule the package-closure link
-- validator applies: it must be relative and must still resolve inside the
-- mutation root once collapsed against the link's own directory. A link is the
-- one entry kind whose /content/ can redirect a later effect, so admitting an
-- ascending target here would reintroduce exactly the escape the retained
-- parent descriptor exists to prevent.
provisioningCreateSymbolicLinkLeaf ::
  ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  FilePath ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningCreateSymbolicLinkLeaf root parentComponents leaf target = do
  validateProvisioningMutationRelativePath parentComponents leaf
  unless
    (safeProvisioningMutationLinkTarget parentComponents target)
    ( Left
        ( ProvisioningMutationRejectedSpec
            "provisioning mutation link target escaped its mutation root"
        )
    )
  pure
    (ProvisioningCreateSymbolicLinkLeaf root parentComponents leaf target)

-- | Whether a symbolic-link target stays inside the mutation root when
-- collapsed against the directory the link itself lives in.
--
-- @parentComponents@ is the link's directory relative to the mutation root, so
-- the collapsed target is @joinPath parentComponents \<\/\> target@. This is the
-- same rule the package-closure walk applies to a copied link, stated against
-- the kernel's component vocabulary rather than a rebuilt pathname.
safeProvisioningMutationLinkTarget :: [FilePath] -> FilePath -> Bool
safeProvisioningMutationLinkTarget parentComponents target =
  not (null target)
    && not (isAbsolute target)
    && '\NUL' `notElem` target
    && length (splitDirectories target) <= maximumProvisioningMutationDepth
    && case splitDirectories
      (normalise (joinPath parentComponents </> target)) of
      ".." : _ -> False
      _ -> True

-- | Test access to 'safeProvisioningMutationLinkTarget'.
safeProvisioningMutationLinkTargetForTest :: [FilePath] -> FilePath -> Bool
safeProvisioningMutationLinkTargetForTest =
  safeProvisioningMutationLinkTarget

provisioningRenameSiblingDirectory ::
  ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  FilePath ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningRenameSiblingDirectory
  root
  parentComponents
  sourceLeaf
  destinationLeaf = do
    validateProvisioningMutationRelativePath parentComponents sourceLeaf
    unless
      (safeProvisioningMutationLeaf destinationLeaf)
      ( Left
          ( ProvisioningMutationRejectedSpec
              "provisioning mutation destination is not one safe leaf"
          )
      )
    unless
      (sourceLeaf /= destinationLeaf)
      ( Left
          ( ProvisioningMutationRejectedSpec
              "provisioning mutation sibling names must differ"
          )
      )
    pure
      ( ProvisioningRenameSiblingDirectory
          root
          parentComponents
          sourceLeaf
          destinationLeaf
      )

provisioningRenameSiblingRegularFile ::
  ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  FilePath ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningRenameSiblingRegularFile
  root
  parentComponents
  sourceLeaf
  destinationLeaf = do
    validateProvisioningMutationRelativePath parentComponents sourceLeaf
    unless
      (safeProvisioningMutationLeaf destinationLeaf)
      ( Left
          ( ProvisioningMutationRejectedSpec
              "provisioning mutation destination is not one safe leaf"
          )
      )
    unless
      (sourceLeaf /= destinationLeaf)
      ( Left
          ( ProvisioningMutationRejectedSpec
              "provisioning mutation sibling names must differ"
          )
      )
    pure
      ( ProvisioningRenameSiblingRegularFile
          root
          parentComponents
          sourceLeaf
          destinationLeaf
      )

-- | Atomically replace an existing regular-file sibling.
--
-- Identical validation to 'provisioningRenameSiblingRegularFile'; the two
-- differ only in the destination precondition the executor enforces.
provisioningReplaceSiblingRegularFile ::
  ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  FilePath ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningReplaceSiblingRegularFile
  root
  parentComponents
  sourceLeaf
  destinationLeaf = do
    validateProvisioningMutationRelativePath parentComponents sourceLeaf
    unless
      (safeProvisioningMutationLeaf destinationLeaf)
      ( Left
          ( ProvisioningMutationRejectedSpec
              "provisioning mutation destination is not one safe leaf"
          )
      )
    unless
      (sourceLeaf /= destinationLeaf)
      ( Left
          ( ProvisioningMutationRejectedSpec
              "provisioning mutation sibling names must differ"
          )
      )
    pure
      ( ProvisioningReplaceSiblingRegularFile
          root
          parentComponents
          sourceLeaf
          destinationLeaf
      )

validateProvisioningMutationRelativePath ::
  [FilePath] ->
  FilePath ->
  Either ProvisioningFilesystemMutationOutcome ()
validateProvisioningMutationRelativePath parentComponents leaf = do
  unless
    ( length parentComponents <= maximumProvisioningMutationDepth
        && all safeProvisioningMutationLeaf parentComponents
    )
    ( Left
        ( ProvisioningMutationRejectedSpec
            "provisioning mutation parent path is not a bounded safe relative path"
        )
    )
  unless
    (safeProvisioningMutationLeaf leaf)
    ( Left
        ( ProvisioningMutationRejectedSpec
            "provisioning mutation target is not one safe leaf"
        )
    )

validProvisioningMutationRootPath :: FilePath -> Bool
validProvisioningMutationRootPath path =
  isAbsolute path
    && normalise path == path
    && '\NUL' `notElem` path

safeProvisioningMutationLeaf :: FilePath -> Bool
safeProvisioningMutationLeaf leaf =
  not (null leaf)
    && leaf `notElem` [".", ".."]
    && takeFileName leaf == leaf
    && '\NUL' `notElem` leaf
    && leaf /= ".materialization.lock"
    && not (".generation-lease-" `List.isPrefixOf` leaf)

safeProvisioningMutationRelativeExecutable :: FilePath -> Bool
safeProvisioningMutationRelativeExecutable executablePath =
  not (null executablePath)
    && not (isAbsolute executablePath)
    && normalise executablePath == executablePath
    && let components = splitDirectories executablePath
        in length components <= maximumProvisioningMutationDepth
             && all safeProvisioningMutationLeaf components

maximumProvisioningMutationDepth :: Int
maximumProvisioningMutationDepth = 128

maximumProvisioningMutationEntries :: Int
maximumProvisioningMutationEntries = 500000

exactMutationDirectoryStatus :: FileStatus -> FileStatus -> Bool
exactMutationDirectoryStatus expected observed =
  isDirectory observed
    && PosixFiles.deviceID expected == PosixFiles.deviceID observed
    && PosixFiles.fileID expected == PosixFiles.fileID observed
    && fileMode expected == fileMode observed

data ProvisioningMutationWireRoot = ProvisioningMutationWireRoot
  { mutationWireRootPath :: !FilePath,
    mutationWireRootDeviceId :: !Integer,
    mutationWireRootFileId :: !Integer,
    mutationWireRootMode :: !Integer
  }
  deriving (Eq, Show)

data ProvisioningMutationWireRequest = ProvisioningMutationWireRequest
  { mutationWireOperation :: !String,
    mutationWireRoot :: !ProvisioningMutationWireRoot,
    mutationWireParentComponents :: ![FilePath],
    mutationWireSourceLeaf :: !FilePath,
    mutationWireDestinationLeaf :: !(Maybe FilePath),
    -- | The symbolic-link target, present only for the link operation. It is a
    -- relative path rather than one leaf, so it cannot share
    -- 'mutationWireDestinationLeaf', whose decoder requires a safe leaf.
    mutationWireLinkTarget :: !(Maybe FilePath)
  }

data ProvisioningMutationWorkingDirectoryWire
  = ProvisioningMutationWorkingDirectoryWire
      !ProvisioningMutationWireRoot
      ![FilePath]
      !(Maybe FilePath)
  deriving (Eq, Show)

instance Aeson.ToJSON ProvisioningMutationWireRoot where
  toJSON root =
    Aeson.object
      [ "path" Aeson..= mutationWireRootPath root,
        "deviceId" Aeson..= mutationWireRootDeviceId root,
        "fileId" Aeson..= mutationWireRootFileId root,
        "mode" Aeson..= mutationWireRootMode root
      ]

instance Aeson.FromJSON ProvisioningMutationWireRoot where
  parseJSON =
    Aeson.withObject "ProvisioningMutationWireRoot" $ \value ->
      ProvisioningMutationWireRoot
        <$> value Aeson..: "path"
        <*> value Aeson..: "deviceId"
        <*> value Aeson..: "fileId"
        <*> value Aeson..: "mode"

instance Aeson.ToJSON ProvisioningMutationWireRequest where
  toJSON request =
    Aeson.object
      [ "version" Aeson..= provisioningMutationWireVersion,
        "operation" Aeson..= mutationWireOperation request,
        "root" Aeson..= mutationWireRoot request,
        "parentComponents"
          Aeson..= mutationWireParentComponents request,
        "sourceLeaf" Aeson..= mutationWireSourceLeaf request,
        "destinationLeaf" Aeson..= mutationWireDestinationLeaf request,
        "linkTarget" Aeson..= mutationWireLinkTarget request
      ]

instance Aeson.FromJSON ProvisioningMutationWireRequest where
  parseJSON =
    Aeson.withObject "ProvisioningMutationWireRequest" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == provisioningMutationWireVersion) $
        fail "unknown provisioning mutation request version"
      ProvisioningMutationWireRequest
        <$> value Aeson..: "operation"
        <*> value Aeson..: "root"
        <*> value Aeson..: "parentComponents"
        <*> value Aeson..: "sourceLeaf"
        <*> value Aeson..: "destinationLeaf"
        <*> value Aeson..: "linkTarget"

-- | The provisioning mutation request version. The parent and the helper are
-- the same self-exec'd binary, so this is an internal coherence marker rather
-- than a compatibility boundary; it moved to 2 when the link operation added
-- its own target field.
provisioningMutationWireVersion :: Int
provisioningMutationWireVersion = 2

instance Aeson.ToJSON ProvisioningMutationWorkingDirectoryWire where
  toJSON
    ( ProvisioningMutationWorkingDirectoryWire
        root
        components
        relativeExecutable
      ) =
      Aeson.object
        [ "root" Aeson..= root,
          "components" Aeson..= components,
          "relativeExecutable" Aeson..= relativeExecutable
        ]

instance Aeson.FromJSON ProvisioningMutationWorkingDirectoryWire where
  parseJSON =
    Aeson.withObject
      "ProvisioningMutationWorkingDirectoryWire"
      ( \value -> do
          root <- value Aeson..: "root"
          components <- value Aeson..: "components"
          relativeExecutable <- value Aeson..: "relativeExecutable"
          unless
            ( length components <= maximumProvisioningMutationDepth
                && all safeProvisioningMutationLeaf components
                && maybe
                  True
                  safeProvisioningMutationRelativeExecutable
                  relativeExecutable
            )
            (fail "invalid provisioning mutation working-directory path")
          _ <-
            either
              (const (fail "invalid provisioning mutation working-directory root"))
              pure
              (provisioningMutationRootFromWire root)
          pure
            ( ProvisioningMutationWorkingDirectoryWire
                root
                components
                relativeExecutable
            )
      )

provisioningMutationWorkingDirectoryWire ::
  ProvisioningMutationWorkingDirectory ->
  ProvisioningMutationWorkingDirectoryWire
provisioningMutationWorkingDirectoryWire
  (ProvisioningMutationWorkingDirectory root components relativeExecutable) =
    ProvisioningMutationWorkingDirectoryWire
      ProvisioningMutationWireRoot
        { mutationWireRootPath =
            provisioningMutationRootPath root,
          mutationWireRootDeviceId =
            provisioningMutationRootDeviceId root,
          mutationWireRootFileId =
            provisioningMutationRootFileId root,
          mutationWireRootMode =
            provisioningMutationRootMode root
        }
      components
      relativeExecutable

provisioningMutationWireRequest ::
  ProvisioningFilesystemMutation ->
  ProvisioningMutationWireRequest
provisioningMutationWireRequest mutation =
  case mutation of
    ProvisioningCreateDirectoryLeaf root parentComponents leaf ->
      wireRequest
        "create-directory-leaf"
        root
        parentComponents
        leaf
        Nothing
        Nothing
    ProvisioningRemoveTreeLeaf root parentComponents leaf ->
      wireRequest "remove-tree-leaf" root parentComponents leaf Nothing Nothing
    ProvisioningRenameSiblingDirectory
      root
      parentComponents
      sourceLeaf
      destinationLeaf ->
        wireRequest
          "rename-sibling-directory"
          root
          parentComponents
          sourceLeaf
          (Just destinationLeaf)
          Nothing
    ProvisioningRenameSiblingRegularFile
      root
      parentComponents
      sourceLeaf
      destinationLeaf ->
        wireRequest
          "rename-sibling-regular-file"
          root
          parentComponents
          sourceLeaf
          (Just destinationLeaf)
          Nothing
    ProvisioningReplaceSiblingRegularFile
      root
      parentComponents
      sourceLeaf
      destinationLeaf ->
        wireRequest
          "replace-sibling-regular-file"
          root
          parentComponents
          sourceLeaf
          (Just destinationLeaf)
          Nothing
    ProvisioningCreateSymbolicLinkLeaf
      root
      parentComponents
      leaf
      target ->
        wireRequest
          "create-symbolic-link-leaf"
          root
          parentComponents
          leaf
          Nothing
          (Just target)
  where
    wireRequest
      operation
      root
      parentComponents
      sourceLeaf
      destinationLeaf
      linkTarget =
        ProvisioningMutationWireRequest
          { mutationWireOperation = operation,
            mutationWireRoot =
              ProvisioningMutationWireRoot
                { mutationWireRootPath =
                    provisioningMutationRootPath root,
                  mutationWireRootDeviceId =
                    provisioningMutationRootDeviceId root,
                  mutationWireRootFileId =
                    provisioningMutationRootFileId root,
                  mutationWireRootMode =
                    provisioningMutationRootMode root
                },
            mutationWireParentComponents = parentComponents,
            mutationWireSourceLeaf = sourceLeaf,
            mutationWireDestinationLeaf = destinationLeaf,
            mutationWireLinkTarget = linkTarget
          }

provisioningMutationFromWire ::
  ProvisioningMutationWireRequest ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningFilesystemMutation
provisioningMutationFromWire request = do
  root <- provisioningMutationRootFromWire (mutationWireRoot request)
  case mutationWireOperation request of
    "create-directory-leaf" -> do
      rejectUnexpectedDestination
      rejectUnexpectedLinkTarget
      provisioningCreateDirectoryLeaf
        root
        (mutationWireParentComponents request)
        (mutationWireSourceLeaf request)
    "remove-tree-leaf" -> do
      rejectUnexpectedDestination
      rejectUnexpectedLinkTarget
      provisioningRemoveTreeLeaf
        root
        (mutationWireParentComponents request)
        (mutationWireSourceLeaf request)
    "rename-sibling-directory" -> do
      rejectUnexpectedLinkTarget
      maybe
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation rename has no destination leaf"
            )
        )
        ( provisioningRenameSiblingDirectory
            root
            (mutationWireParentComponents request)
            (mutationWireSourceLeaf request)
        )
        (mutationWireDestinationLeaf request)
    "rename-sibling-regular-file" -> do
      rejectUnexpectedLinkTarget
      maybe
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation rename has no destination leaf"
            )
        )
        ( provisioningRenameSiblingRegularFile
            root
            (mutationWireParentComponents request)
            (mutationWireSourceLeaf request)
        )
        (mutationWireDestinationLeaf request)
    "replace-sibling-regular-file" -> do
      rejectUnexpectedLinkTarget
      maybe
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation rename has no destination leaf"
            )
        )
        ( provisioningReplaceSiblingRegularFile
            root
            (mutationWireParentComponents request)
            (mutationWireSourceLeaf request)
        )
        (mutationWireDestinationLeaf request)
    "create-symbolic-link-leaf" -> do
      rejectUnexpectedDestination
      maybe
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation link has no target"
            )
        )
        ( provisioningCreateSymbolicLinkLeaf
            root
            (mutationWireParentComponents request)
            (mutationWireSourceLeaf request)
        )
        (mutationWireLinkTarget request)
    _ ->
      Left
        ( ProvisioningMutationRejectedSpec
            "unknown provisioning mutation operation"
        )
  where
    rejectUnexpectedDestination =
      unless
        (isNothing (mutationWireDestinationLeaf request))
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation operation has an unexpected destination"
            )
        )
    rejectUnexpectedLinkTarget =
      unless
        (isNothing (mutationWireLinkTarget request))
        ( Left
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation operation has an unexpected link target"
            )
        )

provisioningMutationRootFromWire ::
  ProvisioningMutationWireRoot ->
  Either
    ProvisioningFilesystemMutationOutcome
    ProvisioningMutationRoot
provisioningMutationRootFromWire wireRoot = do
  unless
    ( validProvisioningMutationRootPath (mutationWireRootPath wireRoot)
        && mutationWireRootDeviceId wireRoot >= 0
        && mutationWireRootFileId wireRoot > 0
        && mutationWireRootMode wireRoot > 0
    )
    ( Left
        ( ProvisioningMutationRejectedSpec
            "invalid provisioning mutation root evidence"
        )
    )
  pure
    ProvisioningMutationRoot
      { provisioningMutationRootPath = mutationWireRootPath wireRoot,
        provisioningMutationRootDeviceId =
          mutationWireRootDeviceId wireRoot,
        provisioningMutationRootFileId =
          mutationWireRootFileId wireRoot,
        provisioningMutationRootMode = mutationWireRootMode wireRoot
      }

instance Aeson.ToJSON ProvisioningMutationHelperOutcome where
  toJSON outcome =
    case outcome of
      ProvisioningMutationHelperSucceeded ->
        Aeson.object ["outcome" Aeson..= ("succeeded" :: String)]
      ProvisioningMutationHelperRejected failure ->
        Aeson.object
          [ "outcome" Aeson..= ("rejected" :: String),
            "failure" Aeson..= failure
          ]
      ProvisioningMutationHelperKernelFailure failure ->
        Aeson.object
          [ "outcome" Aeson..= ("kernel-failure" :: String),
            "failure" Aeson..= failure
          ]

instance Aeson.FromJSON ProvisioningMutationHelperOutcome where
  parseJSON =
    Aeson.withObject "ProvisioningMutationHelperOutcome" $ \value -> do
      outcome <- value Aeson..: "outcome"
      case outcome :: String of
        "succeeded" -> pure ProvisioningMutationHelperSucceeded
        "rejected" ->
          ProvisioningMutationHelperRejected
            <$> value Aeson..: "failure"
        "kernel-failure" ->
          ProvisioningMutationHelperKernelFailure
            <$> value Aeson..: "failure"
        _ -> fail "unknown provisioning mutation helper outcome"

-- | The terminal outcome of a bounded command. Transient command failures are
-- internal retry decisions; an exhausted retry policy resolves to a fatal
-- terminal outcome. Kernel failures remain distinct because no completed child
-- command exists whose stderr or postcondition can safely classify the result.
data CommandOutcome
  = CommandSucceeded !String
  | CommandFailedFatal !String
  | CommandFailedKernel !String
  | CommandTimedOut !Timeout
  deriving (Eq, Show)

data NativeArtifactCachePlan = NativeArtifactCachePlan
  { nativeArtifactCacheRoot :: !FilePath,
    nativeArtifactCacheQuotaBytes :: !Word64,
    nativeArtifactCacheMinioEndpoint :: !Text.Text,
    nativeArtifactCacheModelsBucket :: !Text.Text,
    nativeArtifactCacheDemoArtifactsBucket :: !Text.Text,
    nativeArtifactCacheRegion :: !Text.Text
  }
  deriving (Eq, Show)

nativeArtifactCachePlan ::
  FilePath ->
  Word64 ->
  Text.Text ->
  Text.Text ->
  Text.Text ->
  Text.Text ->
  NativeArtifactCachePlan
nativeArtifactCachePlan = NativeArtifactCachePlan

data NativeArtifactInputPlan
  = NativeArtifactInlineInput !Text.Text
  | NativeArtifactObjectInput !Text.Text
  deriving (Eq, Show)

data NativeArtifactInvocationPlan = NativeArtifactInvocationPlan
  { nativeArtifactPlanModelId :: !Text.Text,
    nativeArtifactPlanSelectedEngine :: !Text.Text,
    nativeArtifactPlanFamily :: !Text.Text,
    nativeArtifactPlanAdapterId :: !Text.Text,
    nativeArtifactPlanRuntimeMode :: !RuntimeMode,
    nativeArtifactPlanInput :: !NativeArtifactInputPlan,
    nativeArtifactPlanCache :: !(Maybe NativeArtifactCachePlan),
    nativeArtifactPlanOutputDirectory :: !(Maybe FilePath),
    nativeArtifactPlanInputFile :: !(Maybe FilePath)
  }
  deriving (Eq, Show)

nativeArtifactInvocationPlan ::
  Text.Text ->
  Text.Text ->
  Text.Text ->
  Text.Text ->
  RuntimeMode ->
  Text.Text ->
  Maybe Text.Text ->
  Maybe NativeArtifactCachePlan ->
  Maybe FilePath ->
  Maybe FilePath ->
  Either String NativeArtifactInvocationPlan
nativeArtifactInvocationPlan
  modelIdentifier
  engineName
  modelFamily
  adapterIdentifier
  mode
  inlineInput
  maybeObjectInput
  maybeCache
  maybeOutputDirectory
  maybeInputFile = do
    mapM_
      requireNativeArtifactText
      [ ("model id", modelIdentifier),
        ("selected engine", engineName),
        ("model family", modelFamily),
        ("adapter id", adapterIdentifier)
      ]
    unless
      ( safeNativeArtifactPathSegment modelIdentifier
          && isJust
            (ArtifactIdentity.parseNativeArtifactIdentity adapterIdentifier)
      )
      (Left "native artifact invocation is outside the closed model/adapter catalog")
    when
      (Text.any (== '\0') inlineInput)
      (Left "native artifact inline input contains NUL")
    mapM_ validateNativeArtifactCachePlan maybeCache
    mapM_
      (validateNativeArtifactAbsolutePath "output directory")
      maybeOutputDirectory
    mapM_
      (validateNativeArtifactAbsolutePath "input file")
      maybeInputFile
    inputPlan <-
      case maybeObjectInput of
        Nothing -> Right (NativeArtifactInlineInput inlineInput)
        Just objectInput -> do
          requireNativeArtifactText ("input object reference", objectInput)
          Right (NativeArtifactObjectInput objectInput)
    pure
      NativeArtifactInvocationPlan
        { nativeArtifactPlanModelId = modelIdentifier,
          nativeArtifactPlanSelectedEngine = engineName,
          nativeArtifactPlanFamily = modelFamily,
          nativeArtifactPlanAdapterId = adapterIdentifier,
          nativeArtifactPlanRuntimeMode = mode,
          nativeArtifactPlanInput = inputPlan,
          nativeArtifactPlanCache = maybeCache,
          nativeArtifactPlanOutputDirectory = maybeOutputDirectory,
          nativeArtifactPlanInputFile = maybeInputFile
        }

requireNativeArtifactText :: (String, Text.Text) -> Either String ()
requireNativeArtifactText (label, value) =
  unless
    (not (Text.null value) && not (Text.any (== '\0') value))
    (Left ("native artifact invocation has an invalid " <> label))

safeNativeArtifactPathSegment :: Text.Text -> Bool
safeNativeArtifactPathSegment value =
  value `notElem` ["", ".", ".."]
    && not (Text.any (`elem` ['/', '\\', '\0']) value)

validateNativeArtifactAbsolutePath ::
  String ->
  FilePath ->
  Either String ()
validateNativeArtifactAbsolutePath label path =
  unless
    (isAbsolute path && '\0' `notElem` path)
    (Left ("native artifact invocation " <> label <> " is not absolute"))

validateNativeArtifactCachePlan ::
  NativeArtifactCachePlan ->
  Either String ()
validateNativeArtifactCachePlan cache = do
  validateNativeArtifactAbsolutePath
    "model-cache root"
    (nativeArtifactCacheRoot cache)
  unless
    (nativeArtifactCacheQuotaBytes cache > 0)
    (Left "native artifact invocation has a non-positive model-cache quota")
  mapM_
    requireNativeArtifactText
    [ ("MinIO endpoint", nativeArtifactCacheMinioEndpoint cache),
      ("models bucket", nativeArtifactCacheModelsBucket cache),
      ( "demo-artifacts bucket",
        nativeArtifactCacheDemoArtifactsBucket cache
      ),
      ("MinIO region", nativeArtifactCacheRegion cache)
    ]

data NativeArtifactOutputStream
  = NativeArtifactStandardOutput
  | NativeArtifactStandardError
  deriving (Eq, Show)

data NativeArtifactCommandOutcome
  = NativeArtifactCommandExited
      !ExitCode
      !ByteString.ByteString
      !ByteString.ByteString
  | NativeArtifactCommandSignaled
      !Int
      !Bool
      !ByteString.ByteString
      !ByteString.ByteString
  | NativeArtifactCommandExceededCeiling !Int
  | NativeArtifactCommandEnforcementUnavailable !Text.Text
  | NativeArtifactCommandOutputLimitExceeded
      !NativeArtifactOutputStream
  | NativeArtifactCommandOutputCaptureFailed
      !NativeArtifactOutputStream
      !Text.Text
  | NativeArtifactCommandTimedOut !Timeout
  | NativeArtifactCommandKernelFailure !Text.Text
  deriving (Eq, Show)

data RetryPolicy
  = NeverRetry
  | BoundedRetry !Int !Int
  deriving (Eq, Show)

data FailureClass
  = FatalFailure
  | TransientThenFatal
  | IdempotentAbsence
  deriving (Eq, Show)

-- | Explicitly test-only kernel probes. Executable paths and scripts are fixed
-- inside this module, so tests cannot reopen an arbitrary spawn surface.
data TestCommand
  = TestEcho !String
  | TestDelayedEcho !FilePath !Int !String
  | TestExit !Int
  | TestSleep !Int
  | TestInvalidUtf8Stdout
  | TestInvalidUtf8Stderr
  | TestOutputOverflow
  | TestIdempotentAbsence !FilePath
  | TestIdempotentFailure !FilePath
  | TestRetryThenSucceed !FilePath
  | TestRetryAlwaysFail !FilePath
  | TestRetryPastDeadline !FilePath
  | TestAcquisitionDeadline !FilePath !FilePath
  | TestAnchorDeathBeforeSupervisorPublication !FilePath
  | TestTargetSetupFailure
  | TestSpawnProcessTree !FilePath
  | TestProtocolIsolationPeer !FilePath !FilePath
  | TestDesignatedOwnerReaping !FilePath !FilePath !FilePath
  | TestSynchronousExceptionProcessTree !FilePath !FilePath
  | TestStopProcessGroup !FilePath
  | TestParentDeathProcessTree !FilePath
  | TestParentDeathStoppedProcessGroup !FilePath
  | TestSupervisorControlFailure
  | TestDurableLeaseOrdering !FilePath !FilePath !FilePath
  | TestPrePreparedOwnerDeath !FilePath !FilePath
  | TestCustodyHandoffOwnerDeath !FilePath !FilePath
  | TestPreLeaseOwnerDeath !FilePath !FilePath
  | TestIncomingActivityRecovery !FilePath !FilePath !FilePath
  | TestIncomingActivityPrewriteRecovery !FilePath !FilePath !FilePath
  | TestIncomingActivityCancellation
      !FilePath
      !FilePath
      !FilePath
      !FilePath
      !FilePath
  | TestProtocolEvidence !TestProtocolEvidenceCase
  | TestExitLeavingDescendant !FilePath
  | TestTerminalFirstStoppedOwnerDeath !FilePath !FilePath
  deriving (Eq, Show)

-- | Closed semantic protocol probes. No constructor accepts raw frame bytes,
-- process specifications, or arbitrary evidence values.
data TestProtocolEvidenceCase
  = ProtocolCaptureAtLimit
  | ProtocolCaptureOverLimit
  | ProtocolTargetExitAtLimit
  | ProtocolTargetExitNegative
  | ProtocolTargetExitOverLimit
  | ProtocolTargetSignalAtLimit
  | ProtocolTargetSignalZero
  | ProtocolTargetSignalNegative
  | ProtocolTargetSignalOverLimit
  | ProtocolSupervisorExitAtLimit
  | ProtocolSupervisorExitNegative
  | ProtocolSupervisorExitOverLimit
  deriving (Eq, Show)

data TestOperation
  = TestQuickOperation
  | TestTimeoutOperation
  | TestStoppedGroupOperation
  | TestRetryOperation
  | TestTotalDeadlineRetryOperation
  | TestAcquisitionDeadlineOperation !FilePath
  | TestAnchorDeathBeforeSupervisorPublicationOperation !FilePath
  | TestTargetSetupFailureOperation
  | TestProtocolIsolationPeerOperation !FilePath
  | TestDesignatedOwnerReapingOperation !FilePath !FilePath
  | TestSynchronousExceptionOperation !FilePath !FilePath
  | TestIdempotentOperation
  | TestSupervisorControlFailureOperation
  | TestDurableLeaseOrderingOperation !FilePath !FilePath
  | TestPrePreparedOwnerDeathOperation !FilePath
  | TestCustodyHandoffOwnerDeathOperation !FilePath
  | TestPreLeaseOwnerDeathOperation !FilePath
  | TestIncomingActivityRecoveryOperation !FilePath !FilePath
  | TestIncomingActivityPrewriteRecoveryOperation !FilePath !FilePath
  | TestIncomingActivityCancellationOperation
      !FilePath
      !FilePath
      !FilePath
      !FilePath
  | TestProtocolEvidenceOperation !TestProtocolEvidenceCase
  | TestTerminalFirstStoppedOwnerDeathOperation !FilePath
  deriving (Eq, Show)

data CommandIdentity
  = ProductionCommandIdentity !ClusterOperation
  | ProvisioningCommandIdentity !Provisioning.ProvisioningOperation
  | ClosedArtifactSmokeCommandIdentity !Provisioning.ProvisioningOperation
  | ProvisioningFilesystemMutationCommandIdentity
  | TestCommandIdentity !TestOperation

data ProvisioningContractObservation = ProvisioningContractObservation
  { provisioningContractOperation :: !Provisioning.ProvisioningOperation,
    provisioningContractExecutable :: !FilePath,
    provisioningContractArguments :: ![String],
    provisioningContractInput :: !String,
    provisioningContractWorkingDirectory :: !(Maybe FilePath),
    provisioningContractEnvironment :: ![(String, String)],
    provisioningContractTimeoutMicros :: !Int,
    provisioningContractRetryPolicy :: !RetryPolicy,
    provisioningContractFailureClass :: !FailureClass
  }
  deriving (Eq, Show)

-- The constructor is hidden. Values originate only from refined generated
-- policies or the isolated fixed policies for kernel probes.
newtype PositiveTimeout = PositiveTimeout Int

data CommandPolicy = CommandPolicy
  { policyPositiveTimeout :: !PositiveTimeout,
    policyRetryPolicy :: !RetryPolicy,
    policyFailureClass :: !FailureClass
  }

commandPolicyTimeout :: CommandPolicy -> Timeout
commandPolicyTimeout policy =
  case policyPositiveTimeout policy of
    PositiveTimeout micros -> Timeout micros

commandPolicyRetryPolicy :: CommandPolicy -> RetryPolicy
commandPolicyRetryPolicy = policyRetryPolicy

commandPolicyFailureClass :: CommandPolicy -> FailureClass
commandPolicyFailureClass = policyFailureClass

-- | Opaque compiled form of the generated host command-policy record. The
-- record shape makes complete production-operation coverage structural rather
-- than a runtime map lookup.
data CommandPolicyPlan = CommandPolicyPlan
  { planKindRead :: !CommandPolicy,
    planKindCreate :: !CommandPolicy,
    planKindDelete :: !CommandPolicy,
    planNvkindCreate :: !CommandPolicy,
    planKubectlRead :: !CommandPolicy,
    planKubectlApply :: !CommandPolicy,
    planKubectlDelete :: !CommandPolicy,
    planKubectlWait :: !CommandPolicy,
    planKubectlExec :: !CommandPolicy,
    planHelmUpgrade :: !CommandPolicy,
    planHelmDependency :: !CommandPolicy,
    planHelmRepository :: !CommandPolicy,
    planHelmRender :: !CommandPolicy,
    planDockerExec :: !CommandPolicy,
    planDockerProbe :: !CommandPolicy,
    planDockerBuild :: !CommandPolicy,
    planDockerInspect :: !CommandPolicy,
    planDockerPull :: !CommandPolicy,
    planDockerTag :: !CommandPolicy,
    planDockerCopy :: !CommandPolicy,
    planDockerStreamImport :: !CommandPolicy,
    planDockerNetwork :: !CommandPolicy,
    planContainerRuntimePull :: !CommandPolicy,
    planHostProbe :: !CommandPolicy,
    planHostMutation :: !CommandPolicy,
    planCurlProbe :: !CommandPolicy,
    planArchiveRead :: !CommandPolicy,
    planGpuUserspaceSync :: !CommandPolicy,
    planImagePublicationLogin :: !CommandPolicy,
    planImagePublicationInspect :: !CommandPolicy,
    planImagePublicationPull :: !CommandPolicy,
    planImagePublicationVerify :: !CommandPolicy,
    planImagePublicationTag :: !CommandPolicy,
    planImagePublicationPush :: !CommandPolicy,
    planImagePublicationRemove :: !CommandPolicy,
    planImagePublicationCopy :: !CommandPolicy
  }

-- | Refine the generated Dhall representation into the positive, bounded
-- quantities consumed by the subprocess kernel.
compileCommandPolicyPlan ::
  HostConfig.DhallCommandPolicies ->
  Either String CommandPolicyPlan
compileCommandPolicyPlan policies =
  CommandPolicyPlan
    <$> refine "kindRead" (HostConfig.dhallKindRead policies)
    <*> refine "kindCreate" (HostConfig.dhallKindCreate policies)
    <*> refine "kindDelete" (HostConfig.dhallKindDelete policies)
    <*> refine "nvkindCreate" (HostConfig.dhallNvkindCreate policies)
    <*> refine "kubectlRead" (HostConfig.dhallKubectlRead policies)
    <*> refine "kubectlApply" (HostConfig.dhallKubectlApply policies)
    <*> refine "kubectlDelete" (HostConfig.dhallKubectlDelete policies)
    <*> refine "kubectlWait" (HostConfig.dhallKubectlWait policies)
    <*> refine "kubectlExec" (HostConfig.dhallKubectlExec policies)
    <*> refine "helmUpgrade" (HostConfig.dhallHelmUpgrade policies)
    <*> refine "helmDependency" (HostConfig.dhallHelmDependency policies)
    <*> refine "helmRepository" (HostConfig.dhallHelmRepository policies)
    <*> refine "helmRender" (HostConfig.dhallHelmRender policies)
    <*> refine "dockerExec" (HostConfig.dhallDockerExec policies)
    <*> refine "dockerProbe" (HostConfig.dhallDockerProbe policies)
    <*> refine "dockerBuild" (HostConfig.dhallDockerBuild policies)
    <*> refine "dockerInspect" (HostConfig.dhallDockerInspect policies)
    <*> refine "dockerPull" (HostConfig.dhallDockerPull policies)
    <*> refine "dockerTag" (HostConfig.dhallDockerTag policies)
    <*> refine "dockerCopy" (HostConfig.dhallDockerCopy policies)
    <*> refine "dockerStreamImport" (HostConfig.dhallDockerStreamImport policies)
    <*> refine "dockerNetwork" (HostConfig.dhallDockerNetwork policies)
    <*> refine "containerRuntimePull" (HostConfig.dhallContainerRuntimePull policies)
    <*> refine "hostProbe" (HostConfig.dhallHostProbe policies)
    <*> refine "hostMutation" (HostConfig.dhallHostMutation policies)
    <*> refine "curlProbe" (HostConfig.dhallCurlProbe policies)
    <*> refine "archiveRead" (HostConfig.dhallArchiveRead policies)
    <*> refine "gpuUserspaceSync" (HostConfig.dhallGpuUserspaceSync policies)
    <*> refine "imagePublicationLogin" (HostConfig.dhallImagePublicationLogin policies)
    <*> refine "imagePublicationInspect" (HostConfig.dhallImagePublicationInspect policies)
    <*> refine "imagePublicationPull" (HostConfig.dhallImagePublicationPull policies)
    <*> refine "imagePublicationVerify" (HostConfig.dhallImagePublicationVerify policies)
    <*> refine "imagePublicationTag" (HostConfig.dhallImagePublicationTag policies)
    <*> refine "imagePublicationPush" (HostConfig.dhallImagePublicationPush policies)
    <*> refine "imagePublicationRemove" (HostConfig.dhallImagePublicationRemove policies)
    <*> refine "imagePublicationCopy" (HostConfig.dhallImagePublicationCopy policies)
  where
    refine operationName =
      refineCommandPolicy ("commandPolicies." <> operationName)

refineCommandPolicy ::
  String ->
  HostConfig.DhallCommandPolicy ->
  Either String CommandPolicy
refineCommandPolicy policyName rawPolicy = do
  timeoutValue <-
    PositiveTimeout
      <$> refinePositiveNatural
        (policyName <> ".timeoutMicros")
        (HostConfig.dhallTimeoutMicros rawPolicy)
  retryPolicy <- refineRetryPolicy policyName (HostConfig.dhallRetry rawPolicy)
  pure
    CommandPolicy
      { policyPositiveTimeout = timeoutValue,
        policyRetryPolicy = retryPolicy,
        policyFailureClass =
          refineFailureClass (HostConfig.dhallFailureClass rawPolicy)
      }

refineRetryPolicy ::
  String ->
  HostConfig.DhallRetryPolicy ->
  Either String RetryPolicy
refineRetryPolicy _ HostConfig.Never = Right NeverRetry
refineRetryPolicy policyName (HostConfig.Bounded boundedRetry) =
  BoundedRetry
    <$> refinePositiveNatural
      (policyName <> ".retry.Bounded.attempts")
      (HostConfig.dhallAttempts boundedRetry)
    <*> refinePositiveNatural
      (policyName <> ".retry.Bounded.backoffMicros")
      (HostConfig.dhallBackoffMicros boundedRetry)

refineFailureClass :: HostConfig.DhallFailureClass -> FailureClass
refineFailureClass failureClass =
  case failureClass of
    HostConfig.Fatal -> FatalFailure
    HostConfig.TransientThenFatal -> TransientThenFatal
    HostConfig.IdempotentAbsence -> IdempotentAbsence

refinePositiveNatural :: String -> Natural -> Either String Int
refinePositiveNatural fieldName rawValue
  | rawValue == 0 =
      Left (fieldName <> " must be positive")
  | rawValue > fromIntegral (maxBound :: Int) =
      Left (fieldName <> " exceeds the supported Int range")
  | otherwise = Right (fromIntegral rawValue)

-- | Select the generated policy for a production operation. Test-only kernel
-- probes use isolated fixed policies and are never represented in HostConfig.
commandPolicyFor :: CommandPolicyPlan -> ClusterOperation -> CommandPolicy
commandPolicyFor plan operation =
  case operation of
    KindReadOperation -> planKindRead plan
    KindCreateOperation -> planKindCreate plan
    KindDeleteOperation -> planKindDelete plan
    NvkindCreateOperation -> planNvkindCreate plan
    KubectlReadOperation -> planKubectlRead plan
    KubectlApplyOperation -> planKubectlApply plan
    KubectlDeleteOperation -> planKubectlDelete plan
    KubectlWaitOperation -> planKubectlWait plan
    KubectlExecOperation -> planKubectlExec plan
    OperatorKubectlOperation -> planKubectlRead plan
    HelmUpgradeOperation -> planHelmUpgrade plan
    HelmDependencyOperation -> planHelmDependency plan
    HelmRepositoryOperation -> planHelmRepository plan
    HelmRenderOperation -> planHelmRender plan
    DockerExecOperation -> planDockerExec plan
    DockerProbeOperation -> planDockerProbe plan
    DockerBuildOperation -> planDockerBuild plan
    DockerInspectOperation -> planDockerInspect plan
    DockerPullOperation -> planDockerPull plan
    DockerTagOperation -> planDockerTag plan
    DockerCopyOperation -> planDockerCopy plan
    DockerStreamImportOperation -> planDockerStreamImport plan
    DockerNetworkOperation -> planDockerNetwork plan
    ContainerRuntimePullOperation -> planContainerRuntimePull plan
    HostProbeOperation -> planHostProbe plan
    HostMutationOperation -> planHostMutation plan
    CurlProbeOperation -> planCurlProbe plan
    ArchiveReadOperation -> planArchiveRead plan
    GpuUserspaceSyncOperation -> planGpuUserspaceSync plan
    ImagePublicationLoginOperation -> planImagePublicationLogin plan
    ImagePublicationInspectOperation -> planImagePublicationInspect plan
    ImagePublicationPullOperation -> planImagePublicationPull plan
    ImagePublicationVerifyOperation -> planImagePublicationVerify plan
    ImagePublicationTagOperation -> planImagePublicationTag plan
    ImagePublicationPushOperation -> planImagePublicationPush plan
    ImagePublicationRemoveOperation -> planImagePublicationRemove plan
    ImagePublicationCopyOperation -> planImagePublicationCopy plan
    -- Sprint 6.44: the model-weight snapshot bootstrap is an upstream fetch
    -- followed by an object-store copy, so it reuses the image-publication copy
    -- policy rather than adding a configurable field: the same long deadline,
    -- bounded retry, and transient-then-fatal classification already describe
    -- that shape, and reusing it keeps the generated host-manifest schema
    -- unchanged for operators who already ran `infernix init`.
    ModelSnapshotBootstrapOperation -> planImagePublicationCopy plan
    -- Sprint 6.44 follow-on: `git ls-files -z` is a fixed local read of the
    -- work tree's index and `node --version` is a fixed local version print.
    -- Both are exactly the host-probe shape the plan already describes — a
    -- short deadline, no retry, fatal on failure — so they reuse it rather
    -- than adding fields that would invalidate every already-generated
    -- `./infernix-host.dhall`.
    SourceInventoryOperation -> planHostProbe plan
    WebToolchainProbeOperation -> planHostProbe plan
    -- The web dependency install downloads and links an entire npm workspace
    -- (PureScript, esbuild, Playwright browsers), so it needs the longest
    -- deadline in the plan. `dockerBuild` already describes that shape — a
    -- 45-minute network-bound build that must not be blindly retried and is
    -- fatal on failure — so it is reused for the same schema-stability reason.
    WebDependencyInstallOperation -> planDockerBuild plan

data PackageClosureSnapshotRole
  = SnapshotPythonHome
  | SnapshotPythonPath
  | SnapshotProjectSource
  | SnapshotArtifactRoot
  deriving (Eq, Show)

data ExactExecutableSnapshotTestPoint
  = MutateBeforeAnchorSnapshot
  | MutateAfterAnchorSnapshot
  deriving (Eq, Show)

data ExecutableSnapshotTestHook = ExecutableSnapshotTestHook
  { snapshotTestPoint :: !ExactExecutableSnapshotTestPoint,
    snapshotTestReadyPath :: !FilePath,
    snapshotTestReleasePath :: !FilePath
  }
  deriving (Eq, Show)

data PackageClosureSnapshotExpectation = PackageClosureSnapshotExpectation
  { closureSnapshotRole :: !PackageClosureSnapshotRole,
    closureSnapshotRoot :: !FilePath,
    closureSnapshotDeviceId :: !Integer,
    closureSnapshotFileId :: !Integer,
    closureSnapshotMode :: !Integer,
    closureSnapshotBytes :: !Integer,
    closureSnapshotFiles :: !Integer,
    closureSnapshotDigest :: !Text.Text
  }
  deriving (Eq, Show)

data RuntimeLibrarySnapshotExpectation = RuntimeLibrarySnapshotExpectation
  { runtimeLibrarySnapshotLeafName :: !FilePath,
    runtimeLibrarySnapshotConfiguredPath :: !FilePath,
    runtimeLibrarySnapshotCanonicalPath :: !FilePath,
    runtimeLibrarySnapshotDeviceId :: !Integer,
    runtimeLibrarySnapshotFileId :: !Integer,
    runtimeLibrarySnapshotMode :: !Integer,
    runtimeLibrarySnapshotSize :: !Integer,
    runtimeLibrarySnapshotDigest :: !Text.Text
  }
  deriving (Eq, Show)

data ExecutableSnapshotExpectation = ExecutableSnapshotExpectation
  { snapshotConfiguredPath :: !FilePath,
    snapshotCanonicalPath :: !FilePath,
    snapshotDeviceId :: !Integer,
    snapshotFileId :: !Integer,
    snapshotMode :: !Integer,
    snapshotSize :: !Integer,
    snapshotDigest :: !Text.Text,
    snapshotPackageClosures ::
      ![PackageClosureSnapshotExpectation],
    snapshotRuntimeLibraries ::
      ![RuntimeLibrarySnapshotExpectation],
    snapshotTestHook :: !(Maybe ExecutableSnapshotTestHook)
  }
  deriving (Eq, Show)

-- | Command-specific wrapper expectation for the Darwin cohort proof. The
-- inner target is deliberately absent: the helper derives it from the closed
-- Apple adapter catalog, so this cannot become a generic nested executable.
data InstalledPythonSourceIsolationExpectation
  = InstalledPythonSourceIsolationExpectation
  { sourceIsolationExpectationAdapter :: !Provisioning.AppleAdapterId,
    sourceIsolationExpectationAuditInjector ::
      !ExecutableSnapshotExpectation,
    sourceIsolationExpectationDirectories ::
      ![PackageClosureSnapshotExpectation],
    sourceIsolationExpectationFiles ::
      ![RuntimeLibrarySnapshotExpectation],
    sourceIsolationExpectationWritableProbe ::
      !RuntimeLibrarySnapshotExpectation,
    sourceIsolationExpectationReceiptDigest :: !Text.Text
  }
  deriving (Eq, Show)

installedPythonSourceIsolationExpectation ::
  Provisioning.AppleAdapterId ->
  Provisioning.InstalledPythonSourceIsolationSpec ->
  InstalledPythonSourceIsolationExpectation
installedPythonSourceIsolationExpectation adapter spec =
  InstalledPythonSourceIsolationExpectation
    { sourceIsolationExpectationAdapter = adapter,
      sourceIsolationExpectationAuditInjector =
        executableSnapshotExpectation
          (Provisioning.installedPythonSourceIsolationAuditInjectorIdentity spec),
      sourceIsolationExpectationDirectories =
        map
          packageClosureSnapshotExpectation
          (Provisioning.installedPythonSourceIsolationDirectories spec),
      sourceIsolationExpectationFiles =
        map
          runtimeLibrarySnapshotExpectation
          (Provisioning.installedPythonSourceIsolationFiles spec),
      sourceIsolationExpectationWritableProbe =
        runtimeLibrarySnapshotExpectation
          (Provisioning.installedPythonSourceIsolationWritableProbeIdentity spec),
      sourceIsolationExpectationReceiptDigest =
        Provisioning.installedPythonSourceIsolationReceiptDigest spec
    }

sourceIsolationExpectationDirectoryPaths ::
  InstalledPythonSourceIsolationExpectation ->
  [FilePath]
sourceIsolationExpectationDirectoryPaths =
  map closureSnapshotRoot . sourceIsolationExpectationDirectories

sourceIsolationExpectationFilePaths ::
  InstalledPythonSourceIsolationExpectation ->
  [FilePath]
sourceIsolationExpectationFilePaths =
  map runtimeLibrarySnapshotCanonicalPath . sourceIsolationExpectationFiles

sourceIsolationExpectationSourcePaths ::
  InstalledPythonSourceIsolationExpectation ->
  [FilePath]
sourceIsolationExpectationSourcePaths expectation =
  sourceIsolationExpectationDirectoryPaths expectation
    <> sourceIsolationExpectationFilePaths expectation

sourceIsolationExpectationPackageIdentity ::
  PackageClosureSnapshotExpectation ->
  Provisioning.ProvisioningPackageClosureIdentity
sourceIsolationExpectationPackageIdentity expectation =
  Provisioning.ProvisioningPackageClosureIdentity
    { Provisioning.provisioningPackageClosureRole =
        case closureSnapshotRole expectation of
          SnapshotPythonHome -> Provisioning.ProvisioningPythonHomeClosure
          SnapshotPythonPath -> Provisioning.ProvisioningPythonPathClosure
          SnapshotProjectSource -> Provisioning.ProvisioningProjectSourceClosure
          SnapshotArtifactRoot -> Provisioning.ProvisioningArtifactRootClosure,
      Provisioning.provisioningPackageClosureRoot = closureSnapshotRoot expectation,
      Provisioning.provisioningPackageClosureDeviceId = closureSnapshotDeviceId expectation,
      Provisioning.provisioningPackageClosureFileId = closureSnapshotFileId expectation,
      Provisioning.provisioningPackageClosureMode = closureSnapshotMode expectation,
      Provisioning.provisioningPackageClosureBytes = closureSnapshotBytes expectation,
      Provisioning.provisioningPackageClosureFiles = closureSnapshotFiles expectation,
      Provisioning.provisioningPackageClosureDigest = closureSnapshotDigest expectation
    }

sourceIsolationExpectationRuntimeIdentity ::
  RuntimeLibrarySnapshotExpectation ->
  Provisioning.ProvisioningRuntimeLibraryIdentity
sourceIsolationExpectationRuntimeIdentity expectation =
  Provisioning.ProvisioningRuntimeLibraryIdentity
    { Provisioning.provisioningRuntimeLibraryLeafName =
        runtimeLibrarySnapshotLeafName expectation,
      Provisioning.provisioningRuntimeLibraryConfiguredPath =
        runtimeLibrarySnapshotConfiguredPath expectation,
      Provisioning.provisioningRuntimeLibraryCanonicalPath =
        runtimeLibrarySnapshotCanonicalPath expectation,
      Provisioning.provisioningRuntimeLibraryDeviceId =
        runtimeLibrarySnapshotDeviceId expectation,
      Provisioning.provisioningRuntimeLibraryFileId =
        runtimeLibrarySnapshotFileId expectation,
      Provisioning.provisioningRuntimeLibraryMode =
        runtimeLibrarySnapshotMode expectation,
      Provisioning.provisioningRuntimeLibrarySize =
        runtimeLibrarySnapshotSize expectation,
      Provisioning.provisioningRuntimeLibraryDigest =
        runtimeLibrarySnapshotDigest expectation
    }

validateInstalledPythonSourceIsolationExpectation ::
  InstalledPythonSourceIsolationExpectation ->
  Either String ()
validateInstalledPythonSourceIsolationExpectation expectation = do
  unless
    (isJust (Provisioning.applePythonAdapterForApple adapter))
    (Left "source-isolation expectation requires a Python Apple adapter")
  unless
    ( length directories == 1
        && length files <= maximumInstalledPythonSourceIsolationFiles
        && length sourcePaths == length (List.nub (map normalise sourcePaths))
        && directories == List.sortOn closureSnapshotRoot directories
        && files == List.sortOn runtimeLibrarySnapshotCanonicalPath files
        && writableProbe `elem` files
    )
    (Left "source-isolation expectation has an invalid bounded source cardinality")
  unless
    ( all validSourcePath sourcePaths
        && all sourceDisjointFromSystemPlatformRoots sourcePaths
        && all validDirectory directories
        && all validFile files
        && writableProbeWithinDirectory
        && validAuditInjector auditInjector
        && canonicalSourceIsolationDigest receiptDigest
        && receiptDigest
          == Provisioning.installedPythonSourceIsolationReceiptDigestFor
            (map sourceIsolationExpectationPackageIdentity directories)
            (map sourceIsolationExpectationRuntimeIdentity files)
    )
    (Left "source-isolation expectation has an invalid exact source identity")
  where
    adapter = sourceIsolationExpectationAdapter expectation
    directories = sourceIsolationExpectationDirectories expectation
    files = sourceIsolationExpectationFiles expectation
    sourcePaths = sourceIsolationExpectationSourcePaths expectation
    receiptDigest = sourceIsolationExpectationReceiptDigest expectation
    auditInjector = sourceIsolationExpectationAuditInjector expectation
    writableProbe = sourceIsolationExpectationWritableProbe expectation
    writableProbeWithinDirectory =
      case directories of
        [directory] ->
          pathWithinOwnedRoot
            (closureSnapshotRoot directory)
            (runtimeLibrarySnapshotCanonicalPath writableProbe)
        _ -> False
    validSourcePath path =
      isAbsolute path
        && normalise path == path
        && '\NUL' `notElem` path
        && length path <= 4096
    sourceDisjointFromSystemPlatformRoots path =
      all
        ( \platformRoot ->
            not
              ( pathWithinOwnedRoot platformRoot path
                  || pathWithinOwnedRoot path platformRoot
              )
        )
        systemPlatformOwnedRoots
    validDirectory directory =
      closureSnapshotRole directory == SnapshotPythonHome
        && closureSnapshotDeviceId directory >= 0
        && closureSnapshotFileId directory > 0
        && closureSnapshotMode directory > 0
        && closureSnapshotBytes directory >= 0
        && closureSnapshotBytes directory
          <= maximumPackageClosureSnapshotBytes
        && closureSnapshotFiles directory > 0
        && closureSnapshotFiles directory <= maximumPackageClosureSnapshotFiles
        && canonicalSourceIsolationDigest (closureSnapshotDigest directory)
    validFile file =
      normalise (runtimeLibrarySnapshotConfiguredPath file)
        == normalise (runtimeLibrarySnapshotCanonicalPath file)
        && safeRuntimeLibraryLeaf (runtimeLibrarySnapshotLeafName file)
        && runtimeLibrarySnapshotDeviceId file >= 0
        && runtimeLibrarySnapshotFileId file > 0
        && runtimeLibrarySnapshotMode file > 0
        && runtimeLibrarySnapshotSize file >= 0
        && runtimeLibrarySnapshotSize file
          <= maximumRuntimeLibrarySnapshotFileBytes
        && canonicalSourceIsolationDigest (runtimeLibrarySnapshotDigest file)
    validAuditInjector identity =
      normalise (snapshotConfiguredPath identity)
        == normalise Provisioning.installedPythonSourceIsolationAuditInjectorExecutable
        && systemPlatformBinaryPath (snapshotCanonicalPath identity)
        && snapshotDeviceId identity >= 0
        && snapshotFileId identity > 0
        && snapshotMode identity > 0
        && snapshotSize identity > 0
        && snapshotSize identity <= maximumExecutableSnapshotBytes
        && canonicalSourceIsolationDigest (snapshotDigest identity)
        && null (snapshotPackageClosures identity)
        && null (snapshotRuntimeLibraries identity)
        && isNothing (snapshotTestHook identity)

executableSnapshotExpectation ::
  Provisioning.ProvisioningExecutableIdentity ->
  ExecutableSnapshotExpectation
executableSnapshotExpectation identity =
  ExecutableSnapshotExpectation
    { snapshotConfiguredPath =
        Provisioning.provisioningExecutableConfiguredPath identity,
      snapshotCanonicalPath =
        Provisioning.provisioningExecutableCanonicalPath identity,
      snapshotDeviceId =
        Provisioning.provisioningExecutableDeviceId identity,
      snapshotFileId =
        Provisioning.provisioningExecutableFileId identity,
      snapshotMode =
        Provisioning.provisioningExecutableMode identity,
      snapshotSize =
        Provisioning.provisioningExecutableSize identity,
      snapshotDigest =
        Provisioning.provisioningExecutableDigest identity,
      snapshotPackageClosures =
        map
          packageClosureSnapshotExpectation
          (Provisioning.provisioningExecutablePackageClosures identity),
      snapshotRuntimeLibraries =
        map
          runtimeLibrarySnapshotExpectation
          (Provisioning.provisioningExecutableRuntimeLibraries identity),
      snapshotTestHook = Nothing
    }

packageClosureSnapshotExpectation ::
  Provisioning.ProvisioningPackageClosureIdentity ->
  PackageClosureSnapshotExpectation
packageClosureSnapshotExpectation identity =
  PackageClosureSnapshotExpectation
    { closureSnapshotRole =
        packageClosureSnapshotRoleForProvisioning
          (Provisioning.provisioningPackageClosureRole identity),
      closureSnapshotRoot =
        Provisioning.provisioningPackageClosureRoot identity,
      closureSnapshotDeviceId =
        Provisioning.provisioningPackageClosureDeviceId identity,
      closureSnapshotFileId =
        Provisioning.provisioningPackageClosureFileId identity,
      closureSnapshotMode =
        Provisioning.provisioningPackageClosureMode identity,
      closureSnapshotBytes =
        Provisioning.provisioningPackageClosureBytes identity,
      closureSnapshotFiles =
        Provisioning.provisioningPackageClosureFiles identity,
      closureSnapshotDigest =
        Provisioning.provisioningPackageClosureDigest identity
    }

packageClosureSnapshotRoleForProvisioning ::
  Provisioning.ProvisioningPackageClosureRole ->
  PackageClosureSnapshotRole
packageClosureSnapshotRoleForProvisioning role =
  case role of
    Provisioning.ProvisioningPythonHomeClosure -> SnapshotPythonHome
    Provisioning.ProvisioningPythonPathClosure -> SnapshotPythonPath
    Provisioning.ProvisioningProjectSourceClosure -> SnapshotProjectSource
    Provisioning.ProvisioningArtifactRootClosure -> SnapshotArtifactRoot

runtimeLibrarySnapshotExpectation ::
  Provisioning.ProvisioningRuntimeLibraryIdentity ->
  RuntimeLibrarySnapshotExpectation
runtimeLibrarySnapshotExpectation identity =
  RuntimeLibrarySnapshotExpectation
    { runtimeLibrarySnapshotLeafName =
        Provisioning.provisioningRuntimeLibraryLeafName identity,
      runtimeLibrarySnapshotConfiguredPath =
        Provisioning.provisioningRuntimeLibraryConfiguredPath identity,
      runtimeLibrarySnapshotCanonicalPath =
        Provisioning.provisioningRuntimeLibraryCanonicalPath identity,
      runtimeLibrarySnapshotDeviceId =
        Provisioning.provisioningRuntimeLibraryDeviceId identity,
      runtimeLibrarySnapshotFileId =
        Provisioning.provisioningRuntimeLibraryFileId identity,
      runtimeLibrarySnapshotMode =
        Provisioning.provisioningRuntimeLibraryMode identity,
      runtimeLibrarySnapshotSize =
        Provisioning.provisioningRuntimeLibrarySize identity,
      runtimeLibrarySnapshotDigest =
        Provisioning.provisioningRuntimeLibraryDigest identity
    }

data RenderedProcess = RenderedProcess
  { renderedExecutable :: !FilePath,
    renderedExecutableIdentity :: !(Maybe ExecutableSnapshotExpectation),
    renderedArguments :: ![String],
    renderedInput :: !String,
    renderedLabel :: !String,
    renderedWorkingDirectory :: !(Maybe FilePath),
    renderedEnvironment :: ![(String, String)]
  }

-- | The type parameter records which closed command language produced the
-- invocation. The constructor and rendered process remain private.
data BoundedCommand command = BoundedCommand
  { boundedCommandValue :: !command,
    boundedCommandIdentity :: !CommandIdentity,
    boundedCommandPolicy :: !CommandPolicy,
    boundedEnvironment :: !SubprocessEnv,
    boundedRenderedCommand :: !RenderedProcess,
    boundedArtifactLeaseExpectation ::
      !(Maybe ArtifactLeaseExpectation),
    boundedArtifactGenerationLeaseExpectation ::
      !(Maybe ArtifactGenerationLeaseExpectation),
    boundedRetainedExecutableExpectation ::
      !(Maybe ExecutableSnapshotExpectation),
    boundedProvisioningMutationWorkingDirectory ::
      !(Maybe ProvisioningMutationWorkingDirectory),
    boundedInstalledPythonSourceIsolationExpectation ::
      !(Maybe InstalledPythonSourceIsolationExpectation)
  }

boundedCommandOperation :: BoundedCommand ClusterCommand -> ClusterOperation
boundedCommandOperation = clusterCommandOperation . boundedCommandValue

boundedOperatorKubectlOperation ::
  BoundedCommand OperatorKubectlCommand ->
  ClusterOperation
boundedOperatorKubectlOperation =
  Command.operatorKubectlOperation . boundedCommandValue

boundedCommandLabel :: BoundedCommand command -> String
boundedCommandLabel =
  renderedLabel . boundedRenderedCommand

compileBoundedCommand ::
  ClusterCommand ->
  SubprocessEnv ->
  Either String (BoundedCommand ClusterCommand)
compileBoundedCommand command environment = do
  Command.validateClusterCommand command
  rendered <- renderProductionCommand environment command
  compileRenderedCommand
    command
    (ProductionCommandIdentity operation)
    policy
    environment
    rendered
  where
    operation = clusterCommandOperation command
    policy =
      commandPolicyFor
        (subprocessEnvCommandPolicyPlan environment)
        operation

compileOperatorKubectlCommand ::
  OperatorKubectlCommand ->
  SubprocessEnv ->
  Either String (BoundedCommand OperatorKubectlCommand)
compileOperatorKubectlCommand command environment = do
  rendered <- renderOperatorCommand environment command
  compileRenderedCommand
    command
    (ProductionCommandIdentity operation)
    policy
    environment
    rendered
  where
    operation = Command.operatorKubectlOperation command
    policy =
      commandPolicyFor
        (subprocessEnvCommandPolicyPlan environment)
        operation

compileTestCommand ::
  TestCommand ->
  SubprocessEnv ->
  Either String (BoundedCommand TestCommand)
compileTestCommand command environment = do
  validateTestCommand command
  let operation = testCommandOperation command
  compileRenderedCommand
    command
    (TestCommandIdentity operation)
    (testCommandPolicy operation)
    environment
    (renderTestCommand command)

compileExactExecutableSnapshotTestCommand ::
  ExactExecutableSnapshotTestPoint ->
  Timeout ->
  FilePath ->
  FilePath ->
  FilePath ->
  SubprocessEnv ->
  IO (Either String (BoundedCommand TestCommand))
compileExactExecutableSnapshotTestCommand
  testPoint
  (Timeout timeoutMicroseconds)
  executablePath
  readyPath
  releasePath
  environment
    | timeoutMicroseconds <= 0 =
        pure (Left "exact executable snapshot test timeout must be positive")
    | not (all isAbsolute [executablePath, readyPath, releasePath]) =
        pure
          (Left "exact executable snapshot test paths must all be absolute")
    | otherwise = do
        observation <-
          try @IOException $ do
            canonicalPath <- canonicalizePath executablePath
            listedStatus <- getSymbolicLinkStatus canonicalPath
            unless
              ( isRegularFile listedStatus
                  && not (isSymbolicLink listedStatus)
                  && fromIntegral (PosixFiles.fileSize listedStatus)
                    <= maximumExecutableSnapshotBytes
                  && PosixFiles.fileMode listedStatus
                    .&. ( PosixFiles.ownerExecuteMode
                            .|. PosixFiles.groupExecuteMode
                            .|. PosixFiles.otherExecuteMode
                        )
                    /= 0
              )
              (ioError (userError "exact snapshot test executable is invalid"))
            digest <- digestSealedSnapshotFile canonicalPath
            finalStatus <- getSymbolicLinkStatus canonicalPath
            unless
              (exactFileStatusMatches listedStatus finalStatus)
              (ioError (userError "exact snapshot test executable changed while observing"))
            pure
              ExecutableSnapshotExpectation
                { snapshotConfiguredPath = executablePath,
                  snapshotCanonicalPath = canonicalPath,
                  snapshotDeviceId =
                    fromIntegral (PosixFiles.deviceID finalStatus),
                  snapshotFileId =
                    fromIntegral (PosixFiles.fileID finalStatus),
                  snapshotMode =
                    fromIntegral (PosixFiles.fileMode finalStatus),
                  snapshotSize =
                    fromIntegral (PosixFiles.fileSize finalStatus),
                  snapshotDigest = digest,
                  snapshotPackageClosures = [],
                  snapshotRuntimeLibraries = [],
                  snapshotTestHook =
                    Just
                      ExecutableSnapshotTestHook
                        { snapshotTestPoint = testPoint,
                          snapshotTestReadyPath = readyPath,
                          snapshotTestReleasePath = releasePath
                        }
                }
        pure $ do
          expectation <-
            either (Left . displayException) Right observation
          bounded <- compileTestCommand (TestEcho "snapshot-test") environment
          let rendered = boundedRenderedCommand bounded
          Right
            bounded
              { boundedCommandPolicy =
                  CommandPolicy
                    (PositiveTimeout timeoutMicroseconds)
                    NeverRetry
                    FatalFailure,
                boundedRenderedCommand =
                  rendered
                    { renderedExecutable = executablePath,
                      renderedExecutableIdentity = Just expectation,
                      renderedArguments = [],
                      renderedLabel = "test exact executable snapshot"
                    }
              }

-- | Compile one package-internal provisioning operation into the same
-- self-exec anchor/supervisor kernel used by cluster commands. The caller must
-- supply a positive per-operation total deadline; provisioning never inherits
-- a retry policy or accepts a rendered process specification.
compileProvisioningCommand ::
  Provisioning.ProvisioningCommand ->
  SubprocessEnv ->
  Timeout ->
  Either String (BoundedCommand Provisioning.ProvisioningCommand)
compileProvisioningCommand command environment (Timeout micros)
  | micros <= 0 =
      Left "bounded provisioning command requires a positive total deadline"
  | otherwise = do
      validateProvisioningCommand command
      rendered <- renderProvisioningCommand environment command
      compileRenderedCommand
        command
        ( ProvisioningCommandIdentity
            (Provisioning.provisioningCommandOperation command)
        )
        (CommandPolicy (PositiveTimeout micros) NeverRetry FatalFailure)
        environment
        rendered

compileProvisioningCommandWithExecutable ::
  Provisioning.ProvisioningCommand ->
  Provisioning.ProvisioningExecutableIdentity ->
  SubprocessEnv ->
  Timeout ->
  Either String (BoundedCommand Provisioning.ProvisioningCommand)
compileProvisioningCommandWithExecutable
  command
  executableIdentity
  environment
  commandTimeout = do
    bounded <- compileProvisioningCommand command environment commandTimeout
    let rendered = boundedRenderedCommand bounded
        expectation =
          executableSnapshotExpectation executableIdentity
        authorizedRendered = rendered
    let packageClosures =
          Provisioning.provisioningExecutablePackageClosures executableIdentity
        runtimeLibraries =
          Provisioning.provisioningExecutableRuntimeLibraries
            executableIdentity
        validPackageClosures =
          validPackageClosureSnapshotAggregate
            (snapshotPackageClosures expectation)
            && validRuntimeLibrarySnapshotAggregate
              (snapshotRuntimeLibraries expectation)
            && validProvisioningRuntimeClosureShape
              command
              (map Provisioning.provisioningPackageClosureRole packageClosures)
              (not (null runtimeLibraries))
    unless
      validPackageClosures
      ( Left
          "bounded provisioning command has an invalid closed runtime-closure shape"
      )
    unless
      ( normalise (renderedExecutable authorizedRendered)
          == normalise
            ( Provisioning.provisioningExecutableConfiguredPath
                executableIdentity
            )
      )
      ( Left
          "resolved executable authority does not match the closed provisioning command"
      )
    pure
      bounded
        { boundedRenderedCommand =
            authorizedRendered
              { renderedExecutableIdentity = Just expectation
              }
        }

compileProvisioningCommandWithExecutableInMutationRoot ::
  Provisioning.ProvisioningCommand ->
  Provisioning.ProvisioningExecutableIdentity ->
  ProvisioningMutationRoot ->
  [FilePath] ->
  SubprocessEnv ->
  Timeout ->
  Either String (BoundedCommand Provisioning.ProvisioningCommand)
compileProvisioningCommandWithExecutableInMutationRoot
  command
  executableIdentity
  mutationRoot
  workingDirectoryComponents
  environment
  commandTimeout = do
    unless
      ( length workingDirectoryComponents
          <= maximumProvisioningMutationDepth
          && all
            safeProvisioningMutationLeaf
            workingDirectoryComponents
      )
      (Left "provisioning mutation working directory is not a bounded safe path")
    bounded <-
      compileProvisioningCommandWithExecutable
        command
        executableIdentity
        environment
        commandTimeout
    let rendered = boundedRenderedCommand bounded
        expectedWorkingDirectory =
          foldl
            (</>)
            (provisioningMutationRootPath mutationRoot)
            workingDirectoryComponents
        configuredExecutable =
          Provisioning.provisioningExecutableConfiguredPath
            executableIdentity
        relativeExecutable =
          makeRelative expectedWorkingDirectory configuredExecutable
        retainExecutable =
          pathWithinOwnedRoot expectedWorkingDirectory configuredExecutable
            && safeProvisioningMutationRelativeExecutable relativeExecutable
    unless
      ( renderedWorkingDirectory rendered
          == Just expectedWorkingDirectory
      )
      ( Left
          "closed provisioning command working directory disagrees with its mutation authority"
      )
    pure
      bounded
        { boundedRenderedCommand =
            rendered
              { renderedWorkingDirectory = Nothing,
                renderedExecutableIdentity =
                  if retainExecutable
                    then Nothing
                    else renderedExecutableIdentity rendered
              },
          boundedRetainedExecutableExpectation =
            if retainExecutable
              then
                Just
                  (executableSnapshotExpectation executableIdentity)
              else Nothing,
          boundedProvisioningMutationWorkingDirectory =
            Just
              ( ProvisioningMutationWorkingDirectory
                  mutationRoot
                  workingDirectoryComponents
                  ( if retainExecutable
                      then Just relativeExecutable
                      else Nothing
                  )
              )
        }

-- | The exact-executable compiler's closed package/runtime shape. An artifact
-- closure may become either a sealed snapshot or, when its executable is under
-- the mutation root, a retained descriptor-backed expectation; both forms
-- require the same single-role input here.
validProvisioningRuntimeClosureShape ::
  Provisioning.ProvisioningCommand ->
  [Provisioning.ProvisioningPackageClosureRole] ->
  Bool ->
  Bool
validProvisioningRuntimeClosureShape command closureRoles hasRuntimeLibraries =
  case command of
    Provisioning.InstallPoetryProject {} ->
      homeClosureCount == 1
        && pathClosureCount >= 1
        && projectSourceClosureCount == 0
        && artifactClosureCount == 0
        && hasRuntimeLibraries
    Provisioning.GeneratePythonProto {} ->
      homeClosureCount == 1
        && pathClosureCount >= 1
        && projectSourceClosureCount == 1
        && artifactClosureCount == 0
        && hasRuntimeLibraries
    _
      | provisioningCommandRequiresArtifactClosure command ->
          artifactClosureCount == 1
            && homeClosureCount == 0
            && pathClosureCount == 0
            && projectSourceClosureCount == 0
            && not hasRuntimeLibraries
      | otherwise ->
          null closureRoles
            && not hasRuntimeLibraries
  where
    closureCount role = length (filter (== role) closureRoles)
    homeClosureCount =
      closureCount Provisioning.ProvisioningPythonHomeClosure
    pathClosureCount =
      closureCount Provisioning.ProvisioningPythonPathClosure
    projectSourceClosureCount =
      closureCount Provisioning.ProvisioningProjectSourceClosure
    artifactClosureCount =
      closureCount Provisioning.ProvisioningArtifactRootClosure

provisioningRuntimeClosureShapeForTest ::
  Provisioning.ProvisioningCommand ->
  [Provisioning.ProvisioningPackageClosureRole] ->
  Bool ->
  Bool
provisioningRuntimeClosureShapeForTest =
  validProvisioningRuntimeClosureShape

provisioningCommandRequiresArtifactClosure ::
  Provisioning.ProvisioningCommand ->
  Bool
provisioningCommandRequiresArtifactClosure command =
  case command of
    Provisioning.ExtractAudiverisJavaCppNatives {} -> True
    Provisioning.SmokeInstalledRunner {} -> True
    Provisioning.SmokeInstalledPythonRunnerSourceIsolated {} -> True
    Provisioning.SmokeLinuxNativeArtifact {} -> True
    _ -> False

resolveProvisioningPoetry :: SubprocessEnv -> Either String FilePath
resolveProvisioningPoetry environment =
  resolveAvailableConfiguredTool environment HostTools.HostPoetry

resolveProvisioningPython ::
  Provisioning.ApplePythonAdapterId ->
  SubprocessEnv ->
  Either String FilePath
resolveProvisioningPython adapter environment =
  resolveAvailableConfiguredTool environment (pythonHostTool adapter)

resolveProvisioningHostNativeCli ::
  Provisioning.AppleAdapterId ->
  SubprocessEnv ->
  Either String FilePath
resolveProvisioningHostNativeCli adapter environment =
  case adapter of
    Provisioning.LlamaCppCliAdapter ->
      resolveAvailableConfiguredTool environment HostTools.HostLlamaCli
    Provisioning.WhisperCppCliAdapter ->
      resolveAvailableConfiguredTool environment HostTools.HostWhisperCli
    _ ->
      Left
        ( "Apple host native CLI resolution is unsupported for "
            <> Provisioning.appleAdapterSlug adapter
        )

resolveProvisioningCommandExecutable ::
  Provisioning.ProvisioningCommand ->
  SubprocessEnv ->
  Either String FilePath
resolveProvisioningCommandExecutable command environment =
  renderedExecutable <$> renderProvisioningCommand environment command

runClosedInstalledRunnerSmoke ::
  Provisioning.AppleAdapterId ->
  ArtifactGenerationLease ->
  ProvisioningMutationRoot ->
  SubprocessEnv ->
  Timeout ->
  IO (Either String NativeArtifactCommandOutcome)
runClosedInstalledRunnerSmoke
  adapter
  generationLease
  artifactRootAuthority
  environment
  commandTimeout =
    case compileClosedInstalledRunnerSmoke of
      Left failure -> pure (Left failure)
      Right bounded ->
        Right <$> runBoundedCommandExactCapture bounded
    where
      artifactRoot = provisioningMutationRootPath artifactRootAuthority
      command = Provisioning.SmokeInstalledRunner adapter artifactRoot
      targetRelativePath =
        Provisioning.installedSmokeExecutableRelativePath adapter
      compileClosedInstalledRunnerSmoke = do
        let (enginesRoot, leaseAdapterId, _generationFingerprint, _payloadDigest) =
              artifactGenerationLeaseFields
                generationLease
            expectedAdapterId =
              Text.pack (Provisioning.appleAdapterSlug adapter)
        unless
          ( enginesRoot == takeDirectory artifactRoot
              && leaseAdapterId == expectedAdapterId
          )
          ( Left
              "installed runner generation lease does not match its exact artifact root and adapter"
          )
        unless
          (safeProvisioningMutationRelativeExecutable targetRelativePath)
          (Left "installed runner target is not one closed relative executable")
        case commandTimeout of
          Timeout micros
            | micros <= 0 ->
                Left "installed runner smoke requires a positive total deadline"
            | otherwise -> do
                validateProvisioningCommand command
                rendered <- renderProvisioningCommand environment command
                let expectedExecutable = artifactRoot </> targetRelativePath
                unless
                  ( renderedExecutable rendered == expectedExecutable
                      && renderedWorkingDirectory rendered == Just artifactRoot
                  )
                  ( Left
                      "installed runner rendering disagrees with its retained root authority"
                  )
                bounded <-
                  compileRenderedCommand
                    command
                    ( ClosedArtifactSmokeCommandIdentity
                        (Provisioning.provisioningCommandOperation command)
                    )
                    (CommandPolicy (PositiveTimeout micros) NeverRetry FatalFailure)
                    environment
                    rendered
                      { renderedWorkingDirectory = Nothing,
                        renderedExecutableIdentity = Nothing
                      }
                pure
                  bounded
                    { boundedArtifactGenerationLeaseExpectation =
                        Just
                          (artifactGenerationLeaseExpectation "apple-silicon" "arm64" generationLease),
                      boundedProvisioningMutationWorkingDirectory =
                        Just
                          ( ProvisioningMutationWorkingDirectory
                              artifactRootAuthority
                              []
                              (Just targetRelativePath)
                          )
                    }

runClosedInstalledPythonSourceIsolationSmoke ::
  Provisioning.AppleAdapterId ->
  ArtifactGenerationLease ->
  ProvisioningMutationRoot ->
  Provisioning.InstalledPythonSourceIsolationSpec ->
  SubprocessEnv ->
  Timeout ->
  IO (Either String NativeArtifactCommandOutcome)
runClosedInstalledPythonSourceIsolationSmoke
  adapter
  generationLease
  artifactRootAuthority
  spec
  environment
  commandTimeout = do
    case compileClosedInstalledPythonSourceIsolationSmoke of
      Left failure -> pure (Left failure)
      Right bounded -> do
        preflight <- try @SomeException verifySourceIdentities
        case preflight of
          Left failure -> synchronousFailure "before launch" failure
          Right () -> do
            outcomeResult <- try @SomeException (runBoundedCommandExactCapture bounded)
            postflight <- try @SomeException verifySourceIdentities
            case (outcomeResult, postflight) of
              (_, Left failure)
                | isJust (fromException failure :: Maybe SomeAsyncException) ->
                    throwIO failure
              (Left failure, _)
                | isJust (fromException failure :: Maybe SomeAsyncException) ->
                    throwIO failure
              (Left failure, _) -> synchronousFailure "while running" failure
              (_, Left failure) -> synchronousFailure "after terminal" failure
              (Right outcome, Right ()) -> pure (Right (validateMarker outcome))
    where
      artifactRoot = provisioningMutationRootPath artifactRootAuthority
      command =
        Provisioning.SmokeInstalledPythonRunnerSourceIsolated
          adapter
          artifactRoot
          spec
      targetRelativePath =
        Provisioning.installedSmokeExecutableRelativePath adapter
      expectation = installedPythonSourceIsolationExpectation adapter spec
      verifySourceIdentities = do
        verifyRetainedPlatformExecutable
          ( executableSnapshotExpectation
              (Provisioning.installedPythonSourceIsolationAuditInjectorIdentity spec)
          )
        mapM_
          (verifyRetainedPackageClosure . packageClosureSnapshotExpectation)
          (Provisioning.installedPythonSourceIsolationDirectories spec)
        mapM_
          (verifyRetainedRuntimeLibrary . runtimeLibrarySnapshotExpectation)
          (Provisioning.installedPythonSourceIsolationFiles spec)
        verifyWritableSourceIsolationProbe
          ( runtimeLibrarySnapshotExpectation
              (Provisioning.installedPythonSourceIsolationWritableProbeIdentity spec)
          )
      synchronousFailure stage failure =
        case fromException failure :: Maybe SomeAsyncException of
          Just _ -> throwIO failure
          Nothing ->
            pure
              ( Left
                  ( "installed Python source isolation identity failed "
                      <> stage
                      <> ": "
                      <> displayException failure
                  )
              )
      validateMarker outcome =
        case outcome of
          NativeArtifactCommandExited ExitSuccess _ stderrBytes ->
            case TextEncoding.decodeUtf8' stderrBytes of
              Left _ ->
                NativeArtifactCommandKernelFailure
                  "installed Python source-isolation stderr is not UTF-8"
              Right stderrText ->
                let expectedMarker =
                      Text.pack (Provisioning.installedPythonSourceIsolationMarker spec)
                    reportedMarkers =
                      filter
                        ("infernix-source-isolation-v1:" `Text.isPrefixOf`)
                        (Text.lines stderrText)
                 in if reportedMarkers == [expectedMarker]
                      then outcome
                      else
                        NativeArtifactCommandKernelFailure
                          "installed Python source-isolation marker is absent, duplicated, or invalid"
          _ -> outcome
      compileClosedInstalledPythonSourceIsolationSmoke = do
        let (enginesRoot, leaseAdapterId, _generationFingerprint, _payloadDigest) =
              artifactGenerationLeaseFields generationLease
            expectedAdapterId = Text.pack (Provisioning.appleAdapterSlug adapter)
        unless
          ( enginesRoot == takeDirectory artifactRoot
              && leaseAdapterId == expectedAdapterId
          )
          ( Left
              "installed Python source-isolation generation lease does not match its exact artifact root and adapter"
          )
        unless
          (safeProvisioningMutationRelativeExecutable targetRelativePath)
          (Left "installed Python source-isolation target is not one closed relative executable")
        case commandTimeout of
          Timeout micros
            | micros <= 0 ->
                Left "installed Python source-isolation smoke requires a positive total deadline"
            | otherwise -> do
                validateProvisioningCommand command
                rendered <- renderProvisioningCommand environment command
                let sandboxIdentity =
                      executableSnapshotExpectation
                        (Provisioning.installedPythonSourceIsolationSandboxIdentity spec)
                unless
                  ( renderedExecutable rendered
                      == Provisioning.installedPythonSourceIsolationSandboxExecutable
                      && renderedWorkingDirectory rendered == Just artifactRoot
                  )
                  ( Left
                      "installed Python source-isolation rendering disagrees with its fixed sandbox and retained root"
                  )
                bounded <-
                  compileRenderedCommand
                    command
                    ( ClosedArtifactSmokeCommandIdentity
                        (Provisioning.provisioningCommandOperation command)
                    )
                    (CommandPolicy (PositiveTimeout micros) NeverRetry FatalFailure)
                    environment
                    rendered
                      { renderedWorkingDirectory = Nothing,
                        renderedExecutableIdentity = Just sandboxIdentity
                      }
                pure
                  bounded
                    { boundedArtifactGenerationLeaseExpectation =
                        Just
                          (artifactGenerationLeaseExpectation "apple-silicon" "arm64" generationLease),
                      boundedProvisioningMutationWorkingDirectory =
                        Just
                          ( ProvisioningMutationWorkingDirectory
                              artifactRootAuthority
                              []
                              Nothing
                          ),
                      boundedInstalledPythonSourceIsolationExpectation =
                        Just expectation
                    }

-- | The Linux image-target smoke.
--
-- @maybeManifestFingerprint@ selects which helper-side validation the retained
-- generation gets. 'Nothing' is a pre-manifest candidate, whose identity the
-- helper rebuilds from its lane, recipe, target contract, and re-observed image
-- evidence. 'Just' is an activated generation whose manifest is already on the
-- final path, so the helper additionally revalidates the whole manifest through
-- 'Artifact.validateEngineArtifactHelperLease' — the production consumer that
-- lease validation previously had none of on this lane.
runClosedLinuxNativeArtifactSmoke ::
  ArtifactIdentity.NativeArtifactIdentity ->
  Text.Text ->
  ArtifactGenerationLease ->
  Maybe Text.Text ->
  ProvisioningMutationRoot ->
  ArtifactTarget.NativeArtifactTargetEvidence ->
  Provisioning.LinuxNativeSmokePolicy ->
  SubprocessEnv ->
  Timeout ->
  IO (Either String NativeArtifactCommandOutcome)
runClosedLinuxNativeArtifactSmoke
  identity
  architecture
  generationLease
  maybeManifestFingerprint
  artifactRootAuthority
  expectedTargetEvidence
  policy
  environment
  commandTimeout =
    case compileClosedLinuxNativeArtifactSmoke of
      Left failure -> pure (Left failure)
      Right bounded -> do
        revalidation <-
          revalidateLinuxNativeTargetEvidence expectedTargetEvidence
        case revalidation of
          Left failure -> pure (Left failure)
          Right () ->
            Right <$> runBoundedCommandExactCapture bounded
    where
      artifactRoot = provisioningMutationRootPath artifactRootAuthority
      command =
        Provisioning.SmokeLinuxNativeArtifact
          identity
          architecture
          artifactRoot
          policy
      compileClosedLinuxNativeArtifactSmoke = do
        let (enginesRoot, leaseAdapterId, _generationFingerprint, _payloadDigest) =
              artifactGenerationLeaseFields
                generationLease
            expectedAdapterId =
              ArtifactIdentity.nativeArtifactAdapterId identity
        unless
          ( enginesRoot == takeDirectory artifactRoot
              && leaseAdapterId == expectedAdapterId
          )
          ( Left
              "Linux native artifact generation lease does not match its exact artifact root and adapter"
          )
        -- A `linux-native` target is an absolute image path, so there is no
        -- artifact-root-relative executable to constrain. The retained root
        -- stays the working directory because it is the generation whose
        -- manifest and recorded loader closure authorize this run; the payload
        -- itself lives in the immutable image, which is a stronger guarantee
        -- than a private copy because it cannot be swapped at all.
        target <-
          ArtifactTarget.nativeArtifactTarget identity "linux-native" architecture
        case commandTimeout of
          Timeout micros
            | micros <= 0 ->
                Left
                  "Linux native artifact smoke requires a positive total deadline"
            | otherwise -> do
                validateProvisioningCommand command
                rendered <- renderProvisioningCommand environment command
                let expectedExecutable =
                      ArtifactTarget.nativeArtifactTargetExecutable
                        artifactRoot
                        target
                unless
                  ( renderedExecutable rendered == expectedExecutable
                      && renderedWorkingDirectory rendered == Just artifactRoot
                  )
                  ( Left
                      "Linux native artifact rendering disagrees with its closed image target"
                  )
                bounded <-
                  compileRenderedCommand
                    command
                    ( ClosedArtifactSmokeCommandIdentity
                        (Provisioning.provisioningCommandOperation command)
                    )
                    (CommandPolicy (PositiveTimeout micros) NeverRetry FatalFailure)
                    environment
                    rendered
                      { renderedWorkingDirectory = Nothing,
                        renderedExecutableIdentity = Nothing
                      }
                pure
                  bounded
                    { boundedArtifactLeaseExpectation =
                        ArtifactLeaseExpectation
                          expectedAdapterId
                          "linux-native"
                          architecture
                          artifactRoot
                          <$> maybeManifestFingerprint,
                      boundedArtifactGenerationLeaseExpectation =
                        Just
                          (artifactGenerationLeaseExpectation "linux-native" architecture generationLease),
                      boundedProvisioningMutationWorkingDirectory =
                        Just
                          ( ProvisioningMutationWorkingDirectory
                              artifactRootAuthority
                              []
                              Nothing
                          )
                    }

-- | Exact parent-side revalidation of a direct native target immediately
-- before its bounded launch: the live configured entry, canonical entry, and
-- canonical bytes must still match the recorded identity.
--
-- Two Sprint 1.20 obligations are deliberately NOT claimed here and remain
-- open: helper-side revalidation of this evidence inside the supervisor, and
-- retirement of the wrapper-shaped @bin\/*@ entrypoint contract so the rendered
-- executable and the recorded direct target are the same path. Until that
-- second correction lands, this revalidation is anchored on the evidence's own
-- recorded configured path rather than on the rendered command.
revalidateNativeArtifactTargetExecutable ::
  ArtifactTarget.NativeArtifactTargetExecutableEvidence ->
  IO (Either String ())
revalidateNativeArtifactTargetExecutable evidence = do
  result <-
    try @IOException $ mask $ \restore -> do
      let configuredPath =
            ArtifactTarget.targetExecutableConfiguredPath evidence
      unless
        (isAbsolute configuredPath)
        (ioError (userError "native target evidence configured path is not absolute"))
      configuredStatus <- getSymbolicLinkStatus configuredPath
      unless
        ( exactTargetEntryMatches
            configuredStatus
            (ArtifactTarget.targetExecutableConfiguredDeviceId evidence)
            (ArtifactTarget.targetExecutableConfiguredFileId evidence)
            (ArtifactTarget.targetExecutableConfiguredMode evidence)
            (ArtifactTarget.targetExecutableConfiguredSize evidence)
        )
        (ioError (userError "native target configured entry disagreed with its evidence"))
      canonicalPath <- restore (canonicalizePath configuredPath)
      unless
        ( isAbsolute canonicalPath
            && normalise canonicalPath
              == normalise
                (ArtifactTarget.targetExecutableCanonicalPath evidence)
        )
        (ioError (userError "native target canonical path disagreed with its evidence"))
      canonicalStatus <- getSymbolicLinkStatus canonicalPath
      unless
        ( isRegularFile canonicalStatus
            && not (isSymbolicLink canonicalStatus)
            && exactTargetEntryMatches
              canonicalStatus
              (ArtifactTarget.targetExecutableCanonicalDeviceId evidence)
              (ArtifactTarget.targetExecutableCanonicalFileId evidence)
              (ArtifactTarget.targetExecutableCanonicalMode evidence)
              (ArtifactTarget.targetExecutableCanonicalSize evidence)
        )
        (ioError (userError "native target canonical entry disagreed with its evidence"))
      descriptor <-
        openFd
          canonicalPath
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              cloexec = True
            }
      finallyPreservingPrimary
        ( restore $ do
            openedStatus <- getFdStatus descriptor
            unless
              (exactFileStatusMatches canonicalStatus openedStatus)
              (ioError (userError "native target changed before exact rehashing"))
            context <-
              hashSnapshotDescriptor
                descriptor
                (fromIntegral (PosixFiles.fileSize openedStatus))
                SHA256.init
            let digest =
                  "sha256:"
                    <> TextEncoding.decodeUtf8
                      (Base16.encode (SHA256.finalize context))
            finalStatus <- getFdStatus descriptor
            finalCanonicalStatus <- getSymbolicLinkStatus canonicalPath
            finalConfiguredStatus <-
              getSymbolicLinkStatus configuredPath
            unless
              ( digest == ArtifactTarget.targetExecutableDigest evidence
                  && exactFileStatusMatches openedStatus finalStatus
                  && exactFileStatusMatches
                    finalStatus
                    finalCanonicalStatus
                  && exactFileStatusMatches
                    configuredStatus
                    finalConfiguredStatus
              )
              (ioError (userError "native target changed during exact rehashing"))
        )
        (ignoreIOException (closeFd descriptor))
  pure (either (Left . displayException) Right result)

exactTargetEntryMatches ::
  FileStatus ->
  Integer ->
  Integer ->
  Integer ->
  Integer ->
  Bool
exactTargetEntryMatches status deviceId fileId mode size =
  fromIntegral (PosixFiles.deviceID status) == deviceId
    && fromIntegral (PosixFiles.fileID status) == fileId
    && fromIntegral (PosixFiles.fileMode status) == mode
    && fromIntegral (PosixFiles.fileSize status) == size

-- | Revalidate every part of an image target's recorded evidence that names
-- live bytes: the entry executable, and the loader closure when the record
-- carries one.
--
-- An image target whose manifest carries no loader closure is refused. The
-- producer emits one for every image target, so an absent closure means the
-- manifest predates that producer and its generation identity does not bind
-- the loader, resolution metadata, or system libraries the target will load.
revalidateLinuxNativeTargetEvidence ::
  ArtifactTarget.NativeArtifactTargetEvidence ->
  IO (Either String ())
revalidateLinuxNativeTargetEvidence evidence = do
  executable <-
    revalidateNativeArtifactTargetExecutable
      (ArtifactTarget.targetEvidenceExecutable evidence)
  case (executable, ArtifactTarget.targetEvidenceLoader evidence) of
    (Left failure, _) -> pure (Left failure)
    (Right (), Nothing) ->
      pure
        ( Left
            "Linux native artifact evidence carries no loader closure"
        )
    (Right (), Just loaderEvidence) ->
      revalidateNativeArtifactTargetLoaderEvidence loaderEvidence

-- | The recorded identity of one loader-closure file, flattened so the object
-- and cache records — which carry the same ten fields under different names —
-- share one revalidator.
data LoaderFileExpectation = LoaderFileExpectation
  { loaderExpectationConfiguredPath :: !FilePath,
    loaderExpectationConfiguredDeviceId :: !Integer,
    loaderExpectationConfiguredFileId :: !Integer,
    loaderExpectationConfiguredMode :: !Integer,
    loaderExpectationConfiguredSize :: !Integer,
    loaderExpectationCanonicalPath :: !FilePath,
    loaderExpectationCanonicalDeviceId :: !Integer,
    loaderExpectationCanonicalFileId :: !Integer,
    loaderExpectationCanonicalMode :: !Integer,
    loaderExpectationCanonicalSize :: !Integer,
    loaderExpectationDigest :: !Text.Text
  }

loaderCacheExpectation ::
  ArtifactTarget.NativeArtifactLoaderFileEvidence ->
  LoaderFileExpectation
loaderCacheExpectation evidence =
  LoaderFileExpectation
    { loaderExpectationConfiguredPath =
        ArtifactTarget.loaderFileConfiguredPath evidence,
      loaderExpectationConfiguredDeviceId =
        ArtifactTarget.loaderFileConfiguredDeviceId evidence,
      loaderExpectationConfiguredFileId =
        ArtifactTarget.loaderFileConfiguredFileId evidence,
      loaderExpectationConfiguredMode =
        ArtifactTarget.loaderFileConfiguredMode evidence,
      loaderExpectationConfiguredSize =
        ArtifactTarget.loaderFileConfiguredSize evidence,
      loaderExpectationCanonicalPath =
        ArtifactTarget.loaderFileCanonicalPath evidence,
      loaderExpectationCanonicalDeviceId =
        ArtifactTarget.loaderFileCanonicalDeviceId evidence,
      loaderExpectationCanonicalFileId =
        ArtifactTarget.loaderFileCanonicalFileId evidence,
      loaderExpectationCanonicalMode =
        ArtifactTarget.loaderFileCanonicalMode evidence,
      loaderExpectationCanonicalSize =
        ArtifactTarget.loaderFileCanonicalSize evidence,
      loaderExpectationDigest = ArtifactTarget.loaderFileDigest evidence
    }

loaderObjectExpectation ::
  ArtifactTarget.NativeArtifactLoaderObjectEvidence ->
  LoaderFileExpectation
loaderObjectExpectation evidence =
  LoaderFileExpectation
    { loaderExpectationConfiguredPath =
        ArtifactTarget.loaderObjectConfiguredPath evidence,
      loaderExpectationConfiguredDeviceId =
        ArtifactTarget.loaderObjectConfiguredDeviceId evidence,
      loaderExpectationConfiguredFileId =
        ArtifactTarget.loaderObjectConfiguredFileId evidence,
      loaderExpectationConfiguredMode =
        ArtifactTarget.loaderObjectConfiguredMode evidence,
      loaderExpectationConfiguredSize =
        ArtifactTarget.loaderObjectConfiguredSize evidence,
      loaderExpectationCanonicalPath =
        ArtifactTarget.loaderObjectCanonicalPath evidence,
      loaderExpectationCanonicalDeviceId =
        ArtifactTarget.loaderObjectCanonicalDeviceId evidence,
      loaderExpectationCanonicalFileId =
        ArtifactTarget.loaderObjectCanonicalFileId evidence,
      loaderExpectationCanonicalMode =
        ArtifactTarget.loaderObjectCanonicalMode evidence,
      loaderExpectationCanonicalSize =
        ArtifactTarget.loaderObjectCanonicalSize evidence,
      loaderExpectationDigest = ArtifactTarget.loaderObjectDigest evidence
    }

-- | Revalidate the complete recorded loader closure immediately before a
-- bounded launch.
--
-- The executable revalidation above proves only that the entry object is
-- unchanged. An image target additionally binds the @PT_INTERP@ loader, the
-- resolution metadata in @\/etc\/ld.so.cache@, and every system library it
-- reaches through @DT_NEEDED@ — none of which lies inside the payload roots the
-- closure digests cover. Each recorded file is therefore re-stat'ed and
-- re-digested against its recorded identity, so a system library replaced
-- between activation and launch fails closed instead of being loaded.
revalidateNativeArtifactTargetLoaderEvidence ::
  ArtifactTarget.NativeArtifactLoaderEvidence ->
  IO (Either String ())
revalidateNativeArtifactTargetLoaderEvidence evidence = do
  result <-
    try @IOException $ do
      mapM_
        (revalidateLoaderFileExpectation . loaderCacheExpectation)
        (ArtifactTarget.loaderEvidenceCache evidence)
      mapM_
        (revalidateLoaderFileExpectation . loaderObjectExpectation)
        (ArtifactTarget.loaderEvidenceObjects evidence)
  pure (either (Left . displayException) Right result)

revalidateLoaderFileExpectation :: LoaderFileExpectation -> IO ()
revalidateLoaderFileExpectation expectation = mask $ \restore -> do
  let configuredPath = loaderExpectationConfiguredPath expectation
  unless
    (isAbsolute configuredPath)
    (ioError (userError "loader closure evidence path is not absolute"))
  configuredStatus <- getSymbolicLinkStatus configuredPath
  unless
    ( exactTargetEntryMatches
        configuredStatus
        (loaderExpectationConfiguredDeviceId expectation)
        (loaderExpectationConfiguredFileId expectation)
        (loaderExpectationConfiguredMode expectation)
        (loaderExpectationConfiguredSize expectation)
    )
    ( ioError
        ( userError
            ("loader closure entry disagreed with its evidence: " <> configuredPath)
        )
    )
  canonicalPath <- restore (canonicalizePath configuredPath)
  unless
    ( isAbsolute canonicalPath
        && normalise canonicalPath
          == normalise (loaderExpectationCanonicalPath expectation)
    )
    ( ioError
        ( userError
            ( "loader closure canonical path disagreed with its evidence: "
                <> configuredPath
            )
        )
    )
  canonicalStatus <- getSymbolicLinkStatus canonicalPath
  unless
    ( isRegularFile canonicalStatus
        && not (isSymbolicLink canonicalStatus)
        && exactTargetEntryMatches
          canonicalStatus
          (loaderExpectationCanonicalDeviceId expectation)
          (loaderExpectationCanonicalFileId expectation)
          (loaderExpectationCanonicalMode expectation)
          (loaderExpectationCanonicalSize expectation)
    )
    ( ioError
        ( userError
            ( "loader closure canonical entry disagreed with its evidence: "
                <> canonicalPath
            )
        )
    )
  descriptor <-
    openFd
      canonicalPath
      ReadOnly
      defaultFileFlags {nofollow = True, cloexec = True}
  finallyPreservingPrimary
    ( restore
        ( revalidateLoaderFileDigest
            expectation
            configuredPath
            canonicalPath
            configuredStatus
            canonicalStatus
            descriptor
        )
    )
    (ignoreIOException (closeFd descriptor))

revalidateLoaderFileDigest ::
  LoaderFileExpectation ->
  FilePath ->
  FilePath ->
  FileStatus ->
  FileStatus ->
  Fd ->
  IO ()
revalidateLoaderFileDigest
  expectation
  configuredPath
  canonicalPath
  configuredStatus
  canonicalStatus
  descriptor = do
    openedStatus <- getFdStatus descriptor
    unless
      (exactFileStatusMatches canonicalStatus openedStatus)
      ( ioError
          ( userError
              ("loader closure file changed before rehashing: " <> canonicalPath)
          )
      )
    context <-
      hashSnapshotDescriptor
        descriptor
        (fromIntegral (PosixFiles.fileSize openedStatus))
        SHA256.init
    let digest =
          "sha256:"
            <> TextEncoding.decodeUtf8 (Base16.encode (SHA256.finalize context))
    finalStatus <- getFdStatus descriptor
    finalCanonicalStatus <- getSymbolicLinkStatus canonicalPath
    finalConfiguredStatus <- getSymbolicLinkStatus configuredPath
    unless
      ( digest == loaderExpectationDigest expectation
          && exactFileStatusMatches openedStatus finalStatus
          && exactFileStatusMatches finalStatus finalCanonicalStatus
          && exactFileStatusMatches configuredStatus finalConfiguredStatus
      )
      ( ioError
          ( userError
              ("loader closure file changed during rehashing: " <> canonicalPath)
          )
      )

-- | Classify one captured stderr line exactly as the installed-runner loader
-- audit does.
parseDyldAuditLineForTest :: String -> Either String DyldAuditLine
parseDyldAuditLineForTest = parseDyldAuditLine

parseElfAuditLineForTest :: String -> Either String ElfAuditLine
parseElfAuditLineForTest = parseElfAuditLine

-- | Validate a sealed Linux generation's @LD_DEBUG=libs@ provenance and return
-- the runner's own diagnostics, exactly as the Linux native smoke does.
sealedLinuxRunnerApplicationOutputForTest ::
  [FilePath] ->
  ByteString.ByteString ->
  Either Text.Text ByteString.ByteString
sealedLinuxRunnerApplicationOutputForTest =
  validateRetainedElfArtifactLoaderEvidence

-- | Which loader a smoke's own run is audited against, derived from its closed
-- provisioning operation. An Apple installed runner and a Linux native artifact
-- must never share an audit.
sealedRunLoaderAuditForTest ::
  Provisioning.ProvisioningOperation ->
  Maybe SealedRunLoaderAudit
sealedRunLoaderAuditForTest =
  sealedRunLoaderAuditFor . ClosedArtifactSmokeCommandIdentity

-- | Validate a sealed generation's loader provenance and return the runner's
-- own diagnostics, exactly as the installed smoke does.
installedRunnerApplicationOutputForTest ::
  [FilePath] ->
  ByteString.ByteString ->
  Either Text.Text ByteString.ByteString
installedRunnerApplicationOutputForTest =
  validateRetainedArtifactLoaderEvidence

-- | The fixed runtime environment a sealed artifact target requires, selected
-- by that target's exact relative position inside its generation.
sealedArtifactRuntimeEnvironmentForTest ::
  FilePath ->
  FilePath ->
  [(String, String)]
sealedArtifactRuntimeEnvironmentForTest =
  artifactSnapshotRuntimeEnvironment

-- | The closed contract a rendered command's extra environment must satisfy.
renderedEnvironmentContractForTest ::
  [(String, String)] ->
  Either String ()
renderedEnvironmentContractForTest = validateRenderedEnvironment

-- | The exact extra environment the production renderer emits for a
-- @linux-native@ artifact smoke, including the fixed guard the rendering
-- wrapper prepends. Exported so the closed contracts are exercised against the
-- shape the renderer produces rather than against a restatement of it.
linuxSealedRunRenderedEnvironmentForTest :: [(String, String)]
linuxSealedRunRenderedEnvironmentForTest = linuxSealedRunRenderedEnvironment

-- | The exact Darwin target environment produced when a snapshotted Python
-- tool runs with the fixed provisioning guard. The snapshot fragment precedes
-- the helper base environment and the fixed renderer appends its guard after
-- it, matching the supervisor's production composition.
darwinPythonSnapshotTargetEnvironmentForTest ::
  FilePath ->
  [(String, String)] ->
  [(String, String)]
darwinPythonSnapshotTargetEnvironmentForTest snapshotRoot helperEnvironment =
  renderPythonPackageClosureSnapshotEnvironment
    PythonClosureNonLinux
    snapshotRoot
    (snapshotRoot </> "python-home")
    [snapshotRoot </> "python-path"]
    [snapshotRoot </> "project-source"]
    True
    <> helperEnvironment
    <> fixedProvisioningRenderedEnvironment []

-- | Re-run the exact closure-environment agreement check used after the
-- anchor has materialized a Darwin Python snapshot. The plan must name the
-- per-anchor root from which the renderer produced its loader paths; naming
-- only the shared parent is deliberately insufficient.
darwinPythonSnapshotClosureEnvironmentContractForTest ::
  FilePath ->
  FilePath ->
  [FilePath] ->
  [FilePath] ->
  [(String, String)] ->
  Either String ()
darwinPythonSnapshotClosureEnvironmentContractForTest
  snapshotRoot
  pythonHome
  pythonPaths
  projectSources =
    validateSealedTargetClosureEnvironment
      ( renderPythonPackageClosureSnapshotEnvironment
          PythonClosureNonLinux
          snapshotRoot
          pythonHome
          pythonPaths
          projectSources
          True
      )

-- | Render the same bounded package-closure disagreement used by the
-- supervisor, from package-internal identity evidence a focused test can
-- construct. This exposes no validation or launch authority.
sealedPackageClosureContentDisagreementForTest ::
  Provisioning.ProvisioningPackageClosureIdentity ->
  Bool ->
  Bool ->
  Integer ->
  Integer ->
  Text.Text ->
  String
sealedPackageClosureContentDisagreementForTest
  identity =
    renderSealedPackageClosureContentDisagreement
      (packageClosureSnapshotExpectation identity)

retainedPackageClosureExcludesFileForTest ::
  Provisioning.ProvisioningPackageClosureRole ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Bool
retainedPackageClosureExcludesFileForTest role =
  packageClosureVerificationExcludesFile
    RetainedPackageClosureSource
    (packageClosureSnapshotRoleForProvisioning role)

sealedPackageClosureExcludesFileForTest ::
  Provisioning.ProvisioningPackageClosureRole ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Bool
sealedPackageClosureExcludesFileForTest role =
  packageClosureVerificationExcludesFile
    SealedPackageClosureSnapshot
    (packageClosureSnapshotRoleForProvisioning role)

retainedPackageClosureExcludesLinkForTest ::
  Provisioning.ProvisioningPackageClosureRole ->
  FilePath ->
  Bool
retainedPackageClosureExcludesLinkForTest role =
  packageClosureVerificationExcludesLink
    RetainedPackageClosureSource
    (packageClosureSnapshotRoleForProvisioning role)

sealedPackageClosureExcludesLinkForTest ::
  Provisioning.ProvisioningPackageClosureRole ->
  FilePath ->
  Bool
sealedPackageClosureExcludesLinkForTest role =
  packageClosureVerificationExcludesLink
    SealedPackageClosureSnapshot
    (packageClosureSnapshotRoleForProvisioning role)

-- | The closed contract a supervised target's environment must satisfy, given
-- the executable snapshot root and any install roots the command's own lease
-- expectations authorize.
supervisorTargetEnvironmentContractForTest ::
  FilePath ->
  [FilePath] ->
  [(String, String)] ->
  [(String, String)] ->
  Either String ()
supervisorTargetEnvironmentContractForTest =
  validateSupervisorTargetEnvironment

provisioningContractForTest ::
  HostConfig.HostConfig ->
  Provisioning.ProvisioningCommand ->
  Timeout ->
  Either String ProvisioningContractObservation
provisioningContractForTest hostConfig command commandTimeout = do
  policyPlan <-
    compileCommandPolicyPlan (HostConfig.hostCommandPolicies hostConfig)
  let environment =
        SubprocessEnv
          { subprocessEnvSearchPath = "/usr/bin:/bin",
            subprocessEnvHome = "/tmp/infernix-contract-home",
            subprocessEnvTmpdir = "/tmp/infernix-contract-tmp",
            subprocessEnvLang = "C.UTF-8",
            subprocessEnvRepoRoot = "/tmp/infernix-contract-repo",
            subprocessEnvRuntimeRoot = "/tmp/infernix-contract-runtime",
            subprocessEnvHelmConfigHome = "/tmp/infernix-contract-helm/config",
            subprocessEnvHelmCacheHome = "/tmp/infernix-contract-helm/cache",
            subprocessEnvHelmDataHome = "/tmp/infernix-contract-helm/data",
            subprocessEnvCommandPolicyPlan = policyPlan,
            subprocessEnvHostConfig = hostConfig,
            subprocessEnvAvailableTools = [minBound .. maxBound]
          }
  bounded <- compileProvisioningCommand command environment commandTimeout
  let rendered = boundedRenderedCommand bounded
      policy = boundedCommandPolicy bounded
      PositiveTimeout timeoutMicros = policyPositiveTimeout policy
  pure
    ProvisioningContractObservation
      { provisioningContractOperation =
          Provisioning.provisioningCommandOperation command,
        provisioningContractExecutable = renderedExecutable rendered,
        provisioningContractArguments = renderedArguments rendered,
        provisioningContractInput = renderedInput rendered,
        provisioningContractWorkingDirectory =
          renderedWorkingDirectory rendered,
        provisioningContractEnvironment = renderedEnvironment rendered,
        provisioningContractTimeoutMicros = timeoutMicros,
        provisioningContractRetryPolicy = policyRetryPolicy policy,
        provisioningContractFailureClass = policyFailureClass policy
      }

pythonHostTool :: Provisioning.ApplePythonAdapterId -> HostTools.HostTool
pythonHostTool adapter =
  case adapter of
    Provisioning.CoreMlPythonAdapter -> HostTools.HostPython311
    _ -> HostTools.HostPython3

compileRenderedCommand ::
  command ->
  CommandIdentity ->
  CommandPolicy ->
  SubprocessEnv ->
  RenderedProcess ->
  Either String (BoundedCommand command)
compileRenderedCommand command identity policy environment rendered
  | null (renderedExecutable rendered) =
      Left "bounded command executable must be non-empty"
  | not (isAbsolute (renderedExecutable rendered)) =
      Left
        ( "bounded command executable must be absolute: "
            <> renderedExecutable rendered
        )
  | Just directory <- renderedWorkingDirectory rendered,
    null directory =
      Left "bounded command generated an empty working directory"
  | Just directory <- renderedWorkingDirectory rendered,
    not (isAbsolute directory) =
      Left ("bounded command working directory must be absolute: " <> directory)
  | otherwise = do
      validateRenderedEnvironment (renderedEnvironment rendered)
      Right
        BoundedCommand
          { boundedCommandValue = command,
            boundedCommandIdentity = identity,
            boundedCommandPolicy = policy,
            boundedEnvironment = environment,
            boundedRenderedCommand = rendered,
            boundedArtifactLeaseExpectation = Nothing,
            boundedArtifactGenerationLeaseExpectation = Nothing,
            boundedRetainedExecutableExpectation = Nothing,
            boundedProvisioningMutationWorkingDirectory = Nothing,
            boundedInstalledPythonSourceIsolationExpectation = Nothing
          }

renderProductionCommand ::
  SubprocessEnv ->
  ClusterCommand ->
  Either String RenderedProcess
renderProductionCommand environment command = do
  validateRequiredTools environment spec
  validateKubeconfigTargets spec
  executable <- resolveConfiguredTool config (Command.renderedCommandTool spec)
  pure (renderedProcessFromSpec environment executable spec)
  where
    config = subprocessEnvHostConfig environment
    spec = Command.renderClusterCommand (configuredToolPath config) command

renderOperatorCommand ::
  SubprocessEnv ->
  OperatorKubectlCommand ->
  Either String RenderedProcess
renderOperatorCommand environment command = do
  validateRequiredTools environment spec
  validateKubeconfigTargets spec
  executable <- resolveConfiguredTool config (Command.renderedCommandTool spec)
  pure (renderedProcessFromSpec environment executable spec)
  where
    config = subprocessEnvHostConfig environment
    spec = Command.renderOperatorKubectlCommand (configuredToolPath config) command

renderedProcessFromSpec ::
  SubprocessEnv ->
  FilePath ->
  Command.RenderedCommandSpec ->
  RenderedProcess
renderedProcessFromSpec environment executable spec =
  RenderedProcess
    { renderedExecutable = executable,
      renderedExecutableIdentity = Nothing,
      renderedArguments = Command.renderedCommandArgv spec,
      renderedInput = Command.renderedCommandStdin spec,
      renderedLabel = Command.renderedCommandLabel spec,
      renderedWorkingDirectory =
        if Command.renderedCommandUsesRepositoryWorkingDirectory spec
          then Just (subprocessEnvRepoRoot environment)
          else Nothing,
      renderedEnvironment = Command.renderedCommandEnvironment spec
    }

validateRenderedEnvironment :: [(String, String)] -> Either String ()
validateRenderedEnvironment environment =
  case environment of
    [] -> Right ()
    _
      | environment == fixedProvisioningRenderedEnvironment [] -> Right ()
    [("KUBECONFIG", kubeconfigPath)] ->
      validateKubeconfigPath kubeconfigPath
    [("KUBECONFIG", kubeconfigPath), ("KUBERC", "off")] ->
      validateKubeconfigPath kubeconfigPath
    _
      | Right () <- validateSealedArtifactRuntimeEnvironment environment ->
          Right ()
    _ ->
      Left "bounded command generated an unsupported command environment"

-- | The runtime environment a sealed artifact's own smoke carries — the three
-- Apple installed-runner shapes and the Linux sealed-run shape.
--
-- Unlike the fixed shapes above, the Apple entries name artifact-root-relative
-- paths, so they are validated structurally: the name set must be exactly one
-- of the closed shapes 'validateSupervisorTargetEnvironment' admits, the fixed
-- guards must hold, and every search-path element must be absolute.
validateSealedArtifactRuntimeEnvironment ::
  [(String, String)] ->
  Either String ()
validateSealedArtifactRuntimeEnvironment environment = do
  unless
    (List.sort (map fst environment) `elem` sealedArtifactRuntimeNameSets)
    (Left "bounded command generated an unsupported command environment")
  unless
    (uniqueEnvironmentNames environment)
    (Left "sealed artifact runtime environment repeats a name")
  mapM_
    requireFixedGuard
    [ ("PYTHONDONTWRITEBYTECODE", "1"),
      ("PYTHONNOUSERSITE", "1"),
      ("DYLD_PRINT_LIBRARIES", "1"),
      ("LD_DEBUG", "libs")
    ]
  mapM_
    requireAbsoluteSearchPath
    ["DYLD_FRAMEWORK_PATH", "DYLD_LIBRARY_PATH", "GGML_BACKEND_PATH", "PYTHONHOME"]
  where
    requireFixedGuard (name, expected) =
      case lookup name environment of
        Nothing -> Right ()
        Just value
          | value == expected -> Right ()
          | otherwise ->
              Left ("sealed artifact runtime " <> name <> " must be " <> expected)
    requireAbsoluteSearchPath name =
      case lookup name environment of
        Nothing -> Right ()
        Just value
          | not (null elements)
              && all (\element -> isAbsolute element && '\NUL' `notElem` element) elements ->
              Right ()
          | otherwise ->
              Left ("sealed artifact runtime " <> name <> " is not an absolute search path")
          where
            elements = filter (not . null) (splitSearchPathElements value)

splitSearchPathElements :: String -> [String]
splitSearchPathElements value =
  case break (== ':') value of
    (element, []) -> [element]
    (element, _ : remaining) -> element : splitSearchPathElements remaining

sealedArtifactRuntimeNameSets :: [[String]]
sealedArtifactRuntimeNameSets =
  List.nub
    ( map
        (List.sort . map fst)
        sealedArtifactRenderedEnvironmentVocabulary
    )

validateKubeconfigPath :: FilePath -> Either String ()
validateKubeconfigPath kubeconfigPath
  | null kubeconfigPath =
      Left "bounded command generated an empty KUBECONFIG path"
  | not (isAbsolute kubeconfigPath) =
      Left
        ( "bounded command KUBECONFIG path must be absolute: "
            <> kubeconfigPath
        )
  | otherwise = Right ()

configuredToolPath :: HostConfig.HostConfig -> HostTools.HostTool -> FilePath
configuredToolPath config =
  Text.unpack . HostTools.hostToolPath config

resolveConfiguredTool ::
  HostConfig.HostConfig ->
  HostTools.HostTool ->
  Either String FilePath
resolveConfiguredTool config tool
  | null configuredPath =
      Left
        ( "configured host tool path is empty for "
            <> Text.unpack (HostTools.hostToolName tool)
        )
  | not (isAbsolute configuredPath) =
      Left
        ( "configured host tool path must be absolute for "
            <> Text.unpack (HostTools.hostToolName tool)
            <> ": "
            <> configuredPath
        )
  | otherwise = Right configuredPath
  where
    configuredPath = configuredToolPath config tool

validateRequiredTools ::
  SubprocessEnv ->
  Command.RenderedCommandSpec ->
  Either String ()
validateRequiredTools environment spec = do
  mapM_
    (resolveAvailableConfiguredTool environment)
    (Command.renderedCommandRequiredTools spec)

resolveAvailableConfiguredTool ::
  SubprocessEnv ->
  HostTools.HostTool ->
  Either String FilePath
resolveAvailableConfiguredTool environment tool = do
  let config = subprocessEnvHostConfig environment
  configuredPath <- resolveConfiguredTool config tool
  if tool `elem` subprocessEnvAvailableTools environment
    then Right configuredPath
    else
      Left
        ( "configured host tool path is not an executable file for "
            <> Text.unpack (HostTools.hostToolName tool)
            <> ": "
            <> configuredPath
        )

-- | Every generated kubeconfig target is an absolute path owned by the
-- recorded cluster state. This validates argv targets as well as Kind's
-- separately validated @KUBECONFIG@ environment, so a public operand
-- constructor cannot reopen caller-relative target selection.
validateKubeconfigTargets ::
  Command.RenderedCommandSpec ->
  Either String ()
validateKubeconfigTargets = go . Command.renderedCommandArgv
  where
    go [] = Right ()
    go ["--kubeconfig"] =
      Left "bounded command generated --kubeconfig without a target path"
    go ("--kubeconfig" : target : rest) =
      validateTarget target >> go rest
    go (token : rest) =
      case List.stripPrefix "--kubeconfig=" token of
        Just target -> validateTarget target >> go rest
        Nothing -> go rest

    validateTarget target
      | null target =
          Left "bounded command generated an empty kubeconfig target"
      | not (isAbsolute target) =
          Left
            ( "bounded command kubeconfig target must be absolute: "
                <> target
            )
      | otherwise = Right ()

validateProvisioningCommand ::
  Provisioning.ProvisioningCommand ->
  Either String ()
validateProvisioningCommand command =
  case command of
    Provisioning.InstallPoetryProject projectDirectory _groups ->
      validateProvisioningPaths
        [("Poetry project install directory", projectDirectory)]
    Provisioning.GeneratePythonProto
      projectDirectory
      repositoryRoot -> do
        validateProvisioningPaths
          [ ("Python proto project directory", projectDirectory),
            ("Python proto repository root", repositoryRoot)
          ]
        unless
          (normalise projectDirectory == normalise (repositoryRoot </> "python"))
          (Left "Python proto project directory must be the repository python root")
    Provisioning.InstallPoetryBootstrap poetryHome ->
      validateProvisioningPath
        "Poetry bootstrap home"
        poetryHome
    Provisioning.ProbePythonVersion _ workingDirectory ->
      validateProvisioningPaths
        [("Python probe working directory", workingDirectory)]
    Provisioning.CreatePythonVenv _ workingDirectory ->
      validateProvisioningPaths
        [("Python venv working directory", workingDirectory)]
    Provisioning.UpgradePinnedPip _ artifactRoot ->
      validateProvisioningPath "pip upgrade artifact root" artifactRoot
    Provisioning.InstallPinnedRequirements _ artifactRoot ->
      validateProvisioningPath "requirements install artifact root" artifactRoot
    Provisioning.DownloadAudiverisDmg workingDirectory dmgPath ->
      validateProvisioningPaths
        [ ("Audiveris download working directory", workingDirectory),
          ("Audiveris DMG path", dmgPath)
        ]
    Provisioning.MountAudiverisDmg workingDirectory dmgPath mountRoot ->
      validateProvisioningPaths
        [ ("Audiveris mount working directory", workingDirectory),
          ("Audiveris DMG path", dmgPath),
          ("Audiveris mount root", mountRoot)
        ]
    Provisioning.DetachAudiverisDmg workingDirectory mountRoot ->
      validateProvisioningPaths
        [ ("Audiveris detach working directory", workingDirectory),
          ("Audiveris mount root", mountRoot)
        ]
    Provisioning.ExtractAudiverisJavaCppNatives artifactRoot ->
      validateProvisioningPath "Audiveris JavaCPP artifact root" artifactRoot
    Provisioning.SmokeInstalledRunner _ artifactRoot ->
      validateProvisioningPath "installed runner artifact root" artifactRoot
    Provisioning.SmokeInstalledPythonRunnerSourceIsolated adapter artifactRoot spec -> do
      validateProvisioningPath "source-isolated installed runner artifact root" artifactRoot
      validateInstalledPythonSourceIsolationSpec adapter artifactRoot spec
    Provisioning.SmokeLinuxNativeArtifact identity architecture artifactRoot _ -> do
      validateProvisioningPath "Linux native artifact root" artifactRoot
      -- Reject an architecture the closed catalog has no entry for here, so a
      -- command that could not render is refused at validation rather than
      -- failing later inside the renderer.
      void
        (ArtifactTarget.nativeArtifactTarget identity "linux-native" architecture)
    Provisioning.QueryPythonVersion _ artifactRoot ->
      validateProvisioningPath "Python version artifact root" artifactRoot
    Provisioning.QueryPythonProvenance _ artifactRoot ->
      validateProvisioningPath "Python provenance artifact root" artifactRoot

validateProvisioningPaths :: [(String, FilePath)] -> Either String ()
validateProvisioningPaths =
  mapM_ (uncurry validateProvisioningPath)

validateProvisioningPath :: String -> FilePath -> Either String ()
validateProvisioningPath label path
  | null path = Left (label <> " must not be empty")
  | '\NUL' `elem` path = Left (label <> " must not contain NUL")
  | not (isAbsolute path) = Left (label <> " must be absolute: " <> path)
  | otherwise = Right ()

renderProvisioningCommand ::
  SubprocessEnv ->
  Provisioning.ProvisioningCommand ->
  Either String RenderedProcess
renderProvisioningCommand environment command =
  case command of
    Provisioning.InstallPoetryProject projectDirectory groups -> do
      poetryExecutable <-
        resolveAvailableConfiguredTool environment HostTools.HostPoetry
      pure
        ( fixedProvisioningProcess
            poetryExecutable
            ( [ "install",
                "--no-interaction",
                "--no-ansi",
                "--directory",
                "."
              ]
                <> case groups of
                  [] -> []
                  _ ->
                    [ "--with",
                      List.intercalate
                        ","
                        (map Provisioning.poetryInstallGroupSlug groups)
                    ]
            )
            ""
            "install exact Poetry project dependency groups"
            projectDirectory
        )
    Provisioning.GeneratePythonProto
      projectDirectory
      repositoryRoot -> do
        pure
          ( fixedProvisioningProcess
              (projectDirectory </> ".venv" </> "bin" </> "python")
              [ "-m",
                "grpc_tools.protoc",
                "-I",
                "proto",
                "--python_out",
                "tools/generated_proto",
                "proto"
                  </> "infernix"
                  </> "manifest"
                  </> "runtime_manifest.proto",
                "proto"
                  </> "infernix"
                  </> "runtime"
                  </> "inference.proto"
              ]
              ""
              "generate fixed Python protobuf bindings"
              repositoryRoot
          )
    Provisioning.InstallPoetryBootstrap poetryHome ->
      pure
        ( fixedProvisioningProcess
            (poetryHome </> Provisioning.fixedVenvPythonRelativePath)
            [ "-m",
              "pip",
              "install",
              "--isolated",
              "--disable-pip-version-check",
              "--no-input",
              "--no-cache-dir",
              "--no-compile",
              "--force-reinstall",
              "--only-binary=:all:",
              "--require-hashes",
              "--index-url",
              "https://pypi.org/simple",
              "-r",
              "-"
            ]
            (unlines Provisioning.pinnedPoetryBootstrapRequirements)
            "install exact hash-locked Poetry bootstrap"
            poetryHome
        )
    Provisioning.ProbePythonVersion
      adapter
      workingDirectory -> do
        pythonExecutable <-
          resolveAvailableConfiguredTool environment (pythonHostTool adapter)
        pure
          ( fixedProvisioningProcess
              pythonExecutable
              ["-c", pythonVersionProbeScript adapter]
              ""
              ("probe Python version for " <> Provisioning.applePythonAdapterSlug adapter)
              workingDirectory
          )
    Provisioning.CreatePythonVenv
      adapter
      workingDirectory -> do
        pythonExecutable <-
          resolveAvailableConfiguredTool environment (pythonHostTool adapter)
        pure
          ( fixedProvisioningProcess
              pythonExecutable
              [ "-m",
                "venv",
                "--clear",
                "--copies",
                provisioningVenvLeaf
              ]
              ""
              ("create Python venv for " <> Provisioning.applePythonAdapterSlug adapter)
              workingDirectory
          )
    Provisioning.UpgradePinnedPip adapter artifactRoot ->
      pure
        ( fixedProvisioningProcess
            (provisioningVenvPython artifactRoot)
            [ "-m",
              "pip",
              "install",
              "--no-compile",
              "--no-input",
              "--upgrade",
              Provisioning.pinnedPipRequirement
            ]
            ""
            ("upgrade pinned pip for " <> Provisioning.applePythonAdapterSlug adapter)
            artifactRoot
        )
    Provisioning.InstallPinnedRequirements adapter artifactRoot ->
      pure
        ( fixedProvisioningProcess
            (provisioningVenvPython artifactRoot)
            ( [ "-m",
                "pip",
                "install",
                "--no-compile",
                "--no-input"
              ]
                <> Provisioning.pinnedPythonRequirements adapter
            )
            ""
            ( "install pinned requirements for "
                <> Provisioning.applePythonAdapterSlug adapter
            )
            artifactRoot
        )
    Provisioning.DownloadAudiverisDmg workingDirectory dmgPath -> do
      relativeDmg <- safeRelativeOperand workingDirectory dmgPath
      pure
        ( fixedProvisioningProcess
            "/usr/bin/curl"
            [ "-fL",
              "--retry",
              "3",
              "--output",
              relativeDmg,
              Provisioning.audiverisDmgUrl
            ]
            ""
            "download pinned Audiveris DMG"
            workingDirectory
        )
    Provisioning.MountAudiverisDmg workingDirectory dmgPath mountRoot -> do
      relativeMount <- safeRelativeOperand workingDirectory mountRoot
      relativeDmg <- safeRelativeOperand workingDirectory dmgPath
      pure
        ( fixedProvisioningProcess
            "/usr/bin/hdiutil"
            [ "attach",
              "-nobrowse",
              "-readonly",
              "-mountpoint",
              relativeMount,
              relativeDmg
            ]
            "Y\n"
            "mount pinned Audiveris DMG"
            workingDirectory
        )
    Provisioning.DetachAudiverisDmg workingDirectory mountRoot -> do
      relativeMount <- safeRelativeOperand workingDirectory mountRoot
      pure
        ( fixedProvisioningProcess
            "/usr/bin/hdiutil"
            ["detach", relativeMount]
            ""
            "detach pinned Audiveris DMG"
            workingDirectory
        )
    Provisioning.ExtractAudiverisJavaCppNatives artifactRoot ->
      pure
        ( fixedProvisioningProcess
            ( artifactRoot
                </> "Audiveris.app"
                </> "Contents"
                </> "runtime"
                </> "Contents"
                </> "Home"
                </> "bin"
                </> "java"
            )
            [ "-Dorg.bytedeco.javacpp.cachedir=" <> (artifactRoot </> "javacpp-cache"),
              "-cp",
              artifactRoot </> "Audiveris.app" </> "Contents" </> "app" </> "*",
              "Audiveris",
              "-version"
            ]
            ""
            "extract Audiveris JavaCPP natives"
            artifactRoot
        )
    Provisioning.SmokeInstalledRunner adapter artifactRoot ->
      -- The installed smoke is the authority that proves the sealed generation
      -- actually loads its own libraries, so it must run under the same fixed
      -- runtime environment the sealed target would get -- including
      -- `DYLD_PRINT_LIBRARIES`, without which the smoke emits no loader
      -- provenance for `validateRetainedArtifactLoaderEvidence` to validate.
      pure
        ( fixedProvisioningProcessWithEnvironment
            ( artifactRoot
                </> Provisioning.installedSmokeExecutableRelativePath adapter
            )
            (Provisioning.installedSmokeArguments adapter artifactRoot)
            ""
            ("smoke installed runner for " <> Provisioning.appleAdapterSlug adapter)
            artifactRoot
            ( artifactSnapshotRuntimeEnvironment
                artifactRoot
                (Provisioning.installedSmokeExecutableRelativePath adapter)
            )
        )
    Provisioning.SmokeInstalledPythonRunnerSourceIsolated adapter artifactRoot spec ->
      -- Launching the platform sandbox strips every outer `DYLD_*` value.
      -- The closed argument renderer therefore restores the exact relocated
      -- Python roots and loader-audit flag through the authenticated
      -- `/usr/bin/env` bridge after the sandbox has started.
      pure
        ( fixedProvisioningProcessWithEnvironment
            Provisioning.installedPythonSourceIsolationSandboxExecutable
            ( Provisioning.installedPythonSourceIsolationArguments
                adapter
                artifactRoot
                spec
            )
            ""
            ( "smoke installed Python runner with its source runtime denied for "
                <> Provisioning.appleAdapterSlug adapter
            )
            artifactRoot
            ( installedPythonSourceIsolationRuntimeEnvironment
                artifactRoot
                (Provisioning.installedSmokeExecutableRelativePath adapter)
            )
        )
    Provisioning.SmokeLinuxNativeArtifact identity architecture artifactRoot policy -> do
      -- The Linux counterpart of the installed smoke's `DYLD_PRINT_LIBRARIES`.
      -- Without it the sealed run emits no loader provenance, so the recorded
      -- ELF loader closure would remain a derivation that nothing ever
      -- confirmed against the real loader.
      --
      -- The executable is the closed catalog's own image target, resolved from
      -- the same `(identity, architecture)` the helper revalidates against, so
      -- the two cannot drift. The artifact root stays the working directory —
      -- it is the generation whose manifest and recorded loader closure
      -- authorize this run — but it is no longer where the executable lives.
      target <-
        ArtifactTarget.nativeArtifactTarget identity "linux-native" architecture
      pure
        ( fixedProvisioningProcessWithEnvironment
            (ArtifactTarget.nativeArtifactTargetExecutable artifactRoot target)
            ( ArtifactTarget.nativeArtifactTargetLeadingArguments
                artifactRoot
                (ArtifactIdentity.nativeArtifactAdapterId identity)
                target
                <> Provisioning.linuxNativeArtifactSmokeArguments identity policy
            )
            ""
            "smoke Linux native artifact"
            artifactRoot
            linuxSealedRunAuditEnvironment
        )
    Provisioning.QueryPythonVersion adapter artifactRoot ->
      pure
        ( fixedProvisioningProcess
            (provisioningVenvPython artifactRoot)
            ["-VV"]
            ""
            ("query Python version for " <> Provisioning.applePythonAdapterSlug adapter)
            artifactRoot
        )
    Provisioning.QueryPythonProvenance adapter artifactRoot ->
      pure
        ( fixedProvisioningProcess
            (provisioningVenvPython artifactRoot)
            ["-m", "pip", "freeze", "--all"]
            ""
            ( "query Python provenance for "
                <> Provisioning.applePythonAdapterSlug adapter
            )
            artifactRoot
        )

validateInstalledPythonSourceIsolationSpec ::
  Provisioning.AppleAdapterId ->
  FilePath ->
  Provisioning.InstalledPythonSourceIsolationSpec ->
  Either String ()
validateInstalledPythonSourceIsolationSpec adapter artifactRoot spec = do
  unless
    (isJust (Provisioning.applePythonAdapterForApple adapter))
    (Left "source-isolated installed smoke requires a Python Apple adapter")
  unless
    ( length directories == 1
        && length files <= maximumInstalledPythonSourceIsolationFiles
        && not (null sourcePaths)
        && length sourcePaths == length (List.nub (map normalise sourcePaths))
        && directories
          == List.sortOn Provisioning.provisioningPackageClosureRoot directories
        && files
          == List.sortOn Provisioning.provisioningRuntimeLibraryCanonicalPath files
        && writableProbe `elem` files
    )
    (Left "source-isolated installed smoke has an invalid bounded source cardinality")
  unless
    ( all validSourcePath sourcePaths
        && all sourceDisjointFromArtifact sourcePaths
        && all sourceDisjointFromSystemPlatformRoots sourcePaths
        && writableProbeWithinDirectory
    )
    (Left "source-isolated installed smoke has an unsafe source path")
  unless
    ( all
        ( (== Provisioning.ProvisioningPythonHomeClosure)
            . Provisioning.provisioningPackageClosureRole
        )
        directories
        && all validDirectoryIdentity directories
        && all validFileIdentity files
    )
    (Left "source-isolated installed smoke has an invalid exact source identity")
  unless
    ( validPlatformIdentity
        Provisioning.installedPythonSourceIsolationSandboxExecutable
        sandboxIdentity
        && validPlatformIdentity
          Provisioning.installedPythonSourceIsolationAuditInjectorExecutable
          auditInjectorIdentity
        && canonicalSourceIsolationDigest receiptDigest
        && receiptDigest
          == Provisioning.installedPythonSourceIsolationReceiptDigestFor
            directories
            files
        && renderedBytes > 0
        && renderedBytes <= maximumInstalledPythonSourceIsolationRenderedBytes
        && not (any (`List.isInfixOf` profile) sourcePaths)
    )
    (Left "source-isolated installed smoke has an invalid fixed wrapper contract")
  where
    directories = Provisioning.installedPythonSourceIsolationDirectories spec
    files = Provisioning.installedPythonSourceIsolationFiles spec
    sourcePaths =
      map Provisioning.provisioningPackageClosureRoot directories
        <> map Provisioning.provisioningRuntimeLibraryCanonicalPath files
    sandboxIdentity =
      Provisioning.installedPythonSourceIsolationSandboxIdentity spec
    auditInjectorIdentity =
      Provisioning.installedPythonSourceIsolationAuditInjectorIdentity spec
    writableProbe =
      Provisioning.installedPythonSourceIsolationWritableProbeIdentity spec
    writableProbeWithinDirectory =
      case directories of
        [directory] ->
          pathWithinOwnedRoot
            (Provisioning.provisioningPackageClosureRoot directory)
            (Provisioning.provisioningRuntimeLibraryCanonicalPath writableProbe)
        _ -> False
    receiptDigest =
      Provisioning.installedPythonSourceIsolationReceiptDigest spec
    profile = Provisioning.installedPythonSourceIsolationProfile spec
    renderedBytes =
      sum
        ( map
            length
            ( Provisioning.installedPythonSourceIsolationArguments
                adapter
                artifactRoot
                spec
            )
        )
    validSourcePath path =
      isAbsolute path
        && normalise path == path
        && '\NUL' `notElem` path
        && length path <= 4096
    sourceDisjointFromArtifact path =
      not
        ( pathWithinOwnedRoot path artifactRoot
            || pathWithinOwnedRoot artifactRoot path
        )
    sourceDisjointFromSystemPlatformRoots path =
      all
        ( \platformRoot ->
            not
              ( pathWithinOwnedRoot platformRoot path
                  || pathWithinOwnedRoot path platformRoot
              )
        )
        systemPlatformOwnedRoots
    validDirectoryIdentity identity =
      Provisioning.provisioningPackageClosureDeviceId identity >= 0
        && Provisioning.provisioningPackageClosureFileId identity > 0
        && Provisioning.provisioningPackageClosureMode identity > 0
        && Provisioning.provisioningPackageClosureBytes identity >= 0
        && Provisioning.provisioningPackageClosureBytes identity
          <= maximumPackageClosureSnapshotBytes
        && Provisioning.provisioningPackageClosureFiles identity > 0
        && Provisioning.provisioningPackageClosureFiles identity <= 100000
        && canonicalSourceIsolationDigest
          (Provisioning.provisioningPackageClosureDigest identity)
    validFileIdentity identity =
      let configured = Provisioning.provisioningRuntimeLibraryConfiguredPath identity
          canonical = Provisioning.provisioningRuntimeLibraryCanonicalPath identity
       in normalise configured == normalise canonical
            && Provisioning.provisioningRuntimeLibraryDeviceId identity >= 0
            && Provisioning.provisioningRuntimeLibraryFileId identity > 0
            && Provisioning.provisioningRuntimeLibraryMode identity > 0
            && Provisioning.provisioningRuntimeLibrarySize identity >= 0
            && Provisioning.provisioningRuntimeLibrarySize identity
              <= maximumRuntimeLibrarySnapshotFileBytes
            && canonicalSourceIsolationDigest
              (Provisioning.provisioningRuntimeLibraryDigest identity)
    validPlatformIdentity expectedConfiguredPath identity =
      normalise (Provisioning.provisioningExecutableConfiguredPath identity)
        == normalise expectedConfiguredPath
        && systemPlatformBinaryPath
          (Provisioning.provisioningExecutableCanonicalPath identity)
        && Provisioning.provisioningExecutableDeviceId identity >= 0
        && Provisioning.provisioningExecutableFileId identity > 0
        && Provisioning.provisioningExecutableMode identity > 0
        && Provisioning.provisioningExecutableSize identity > 0
        && Provisioning.provisioningExecutableSize identity
          <= maximumExecutableSnapshotBytes
        && canonicalSourceIsolationDigest
          (Provisioning.provisioningExecutableDigest identity)
        && null (Provisioning.provisioningExecutablePackageClosures identity)
        && null (Provisioning.provisioningExecutableRuntimeLibraries identity)

maximumInstalledPythonSourceIsolationFiles :: Int
maximumInstalledPythonSourceIsolationFiles = 512

maximumInstalledPythonSourceIsolationRenderedBytes :: Int
maximumInstalledPythonSourceIsolationRenderedBytes = 256 * 1024

canonicalSourceIsolationDigest :: Text.Text -> Bool
canonicalSourceIsolationDigest digest =
  case Text.stripPrefix "sha256:" digest of
    Just suffix ->
      Text.length suffix == 64
        && Text.all (`Text.elem` "0123456789abcdef") suffix
    Nothing -> False

systemPlatformExecutableRoots :: [FilePath]
systemPlatformExecutableRoots =
  [ "/bin",
    "/sbin",
    "/usr/bin",
    "/usr/sbin",
    "/usr/libexec",
    "/System"
  ]

systemDyldLibraryRoots :: [FilePath]
systemDyldLibraryRoots =
  [ "/usr/lib",
    "/System/Library",
    "/System/Cryptexes",
    "/System/Volumes/Preboot/Cryptexes",
    "/Library/Apple/System/Library"
  ]

systemPlatformOwnedRoots :: [FilePath]
systemPlatformOwnedRoots =
  List.nub (systemPlatformExecutableRoots <> systemDyldLibraryRoots)

pythonVersionProbeScript :: Provisioning.ApplePythonAdapterId -> String
pythonVersionProbeScript adapter =
  case adapter of
    Provisioning.CoreMlPythonAdapter ->
      "import platform,sys; v=sys.version_info[:2]; print(platform.python_version()); raise SystemExit(0 if v == (3, 11) else 1)"
    _ ->
      "import platform,sys; v=sys.version_info[:2]; print(platform.python_version()); raise SystemExit(0 if v == (3, 12) else 1)"

-- | The venv's own leaf, which is what the external tool receives.
--
-- The target enters its working directory by @fchdir@ on a retained
-- descriptor, so an absolute operand would be re-resolved from @\/@ and defeat
-- that anchoring entirely. Every rendered operand under a descriptor-derived
-- working directory must therefore be relative to it.
provisioningVenvLeaf :: FilePath
provisioningVenvLeaf = "venv"

-- | Re-express one absolute operand as a safe path relative to the command's
-- descriptor-derived working directory.
--
-- The working directory is entered with @fchdir@ on a descriptor that was
-- validated component by component, so a relative operand resolves inside the
-- directory that was actually checked. An absolute operand resolves from the
-- filesystem root instead, which is exactly the re-resolution the retained
-- descriptor exists to prevent. An operand outside the working directory, or
-- one whose relative form would ascend, is refused rather than passed through.
-- | The rendered-operand rule, exposed so a deterministic test can prove it
-- refuses an operand outside the command's descriptor-derived working
-- directory rather than passing it through as an absolute path.
safeRelativeOperandForTest :: FilePath -> FilePath -> Either String FilePath
safeRelativeOperandForTest = safeRelativeOperand

safeRelativeOperand :: FilePath -> FilePath -> Either String FilePath
safeRelativeOperand workingDirectory operand
  | not (isAbsolute workingDirectory) =
      Left "provisioning working directory is not absolute"
  | not (isAbsolute operand) =
      Left "provisioning operand is already relative"
  | null relative
      || isAbsolute relative
      || any (`elem` [".", ".."]) (splitDirectories relative) =
      Left ("provisioning operand escapes its working directory: " <> operand)
  | otherwise = Right relative
  where
    relative =
      makeRelative (normalise workingDirectory) (normalise operand)

provisioningVenvPython :: FilePath -> FilePath
provisioningVenvPython artifactRoot =
  artifactRoot </> Provisioning.fixedVenvPythonRelativePath

fixedProvisioningProcess ::
  FilePath ->
  [String] ->
  String ->
  String ->
  FilePath ->
  RenderedProcess
fixedProvisioningProcess executable arguments input label workingDirectory =
  fixedProvisioningProcessWithEnvironment
    executable
    arguments
    input
    label
    workingDirectory
    []

-- | A fixed provisioning process that additionally carries the closed runtime
-- environment its target requires. The bytecode guard is always present; the
-- supplied entries must keep the whole environment inside one of the closed
-- rendered shapes 'validateSupervisorTargetEnvironment' admits.
fixedProvisioningProcessWithEnvironment ::
  FilePath ->
  [String] ->
  String ->
  String ->
  FilePath ->
  [(String, String)] ->
  RenderedProcess
fixedProvisioningProcessWithEnvironment
  executable
  arguments
  input
  label
  workingDirectory
  runtimeEnvironment =
    RenderedProcess
      { renderedExecutable = executable,
        renderedExecutableIdentity = Nothing,
        renderedArguments = arguments,
        renderedInput = input,
        renderedLabel = label,
        renderedWorkingDirectory = Just workingDirectory,
        renderedEnvironment =
          fixedProvisioningRenderedEnvironment runtimeEnvironment
      }

fixedProvisioningRenderedEnvironment ::
  [(String, String)] ->
  [(String, String)]
fixedProvisioningRenderedEnvironment runtimeEnvironment =
  provisioningFixedEnvironmentGuard : runtimeEnvironment

-- | The guard every fixed provisioning process carries. Named because the
-- closed environment contracts must be written against the same value the
-- renderer prepends: a contract that omits it describes a shape no rendered
-- command can have.
provisioningFixedEnvironmentGuard :: (String, String)
provisioningFixedEnvironmentGuard = ("PYTHONDONTWRITEBYTECODE", "1")

-- | The loader audit a sealed @linux-native@ run carries, and the complete
-- extra environment the renderer therefore produces for it.
--
-- Both closed contracts derive their Linux name set from
-- 'linuxSealedRunRenderedEnvironment', and the renderer passes
-- 'linuxSealedRunAuditEnvironment' to the wrapper that prepends the same guard,
-- so the shape the renderer emits and the shapes the validators admit cannot
-- drift apart. They previously did: the contracts named @LD_DEBUG@ alone while
-- every rendered command also carries the guard, so the Linux native artifact
-- smoke was refused as an unsupported command environment on every input.
linuxSealedRunAuditEnvironment :: [(String, String)]
linuxSealedRunAuditEnvironment = [("LD_DEBUG", "libs")]

linuxSealedRunRenderedEnvironment :: [(String, String)]
linuxSealedRunRenderedEnvironment =
  fixedProvisioningRenderedEnvironment linuxSealedRunAuditEnvironment

validateTestCommand :: TestCommand -> Either String ()
validateTestCommand testCommand =
  case testCommand of
    TestEcho _ -> Right ()
    TestDelayedEcho readyPath secondsToSleep _
      | null readyPath -> Left "test delayed-echo command requires a ready path"
      | secondsToSleep < 0 ->
          Left "test delayed-echo command requires non-negative seconds"
      | otherwise -> Right ()
    TestExit exitCode
      | exitCode > 0 -> Right ()
      | otherwise -> Left "test exit command requires a positive non-zero exit code"
    TestSleep secondsToSleep
      | secondsToSleep >= 0 -> Right ()
      | otherwise -> Left "test sleep command requires non-negative seconds"
    TestInvalidUtf8Stdout -> Right ()
    TestInvalidUtf8Stderr -> Right ()
    TestOutputOverflow -> Right ()
    TestIdempotentAbsence markerPath
      | null markerPath -> Left "test idempotent-absence command requires a marker path"
      | otherwise -> Right ()
    TestIdempotentFailure markerPath
      | null markerPath -> Left "test idempotent-failure command requires a marker path"
      | otherwise -> Right ()
    TestRetryThenSucceed markerPath
      | null markerPath -> Left "test retry command requires a marker path"
      | otherwise -> Right ()
    TestRetryAlwaysFail markerPath
      | null markerPath -> Left "test exhausted-retry command requires a marker path"
      | otherwise -> Right ()
    TestRetryPastDeadline markerPath
      | null markerPath -> Left "test total-deadline retry command requires a marker path"
      | otherwise -> Right ()
    TestAcquisitionDeadline readyPath executedPath -> do
      validateAbsoluteTestPath
        "test acquisition-deadline ready"
        readyPath
      validateAbsoluteTestPath
        "test acquisition-deadline executed"
        executedPath
    TestAnchorDeathBeforeSupervisorPublication readyPath ->
      validateAbsoluteTestPath
        "test anchor pre-publication death ready"
        readyPath
    TestTargetSetupFailure -> Right ()
    TestSpawnProcessTree childPidPath
      | null childPidPath -> Left "test process-tree command requires a child pid path"
      | otherwise -> Right ()
    TestProtocolIsolationPeer readyPath releasePath -> do
      validateAbsoluteTestPath
        "test protocol-isolation exact-identity ready"
        readyPath
      validateAbsoluteTestPath
        "test protocol-isolation release FIFO"
        releasePath
    TestDesignatedOwnerReaping readyPath releasePath evidencePrefix -> do
      validateAbsoluteTestPath
        "test designated-owner reap ready"
        readyPath
      validateAbsoluteTestPath
        "test designated-owner reap release FIFO"
        releasePath
      validateAbsoluteTestPath
        "test designated-owner reap evidence prefix"
        evidencePrefix
    TestSynchronousExceptionProcessTree identityPath releaseFifo -> do
      validateAbsoluteTestPath
        "test synchronous-exception exact identity"
        identityPath
      validateAbsoluteTestPath
        "test synchronous-exception release FIFO"
        releaseFifo
    TestStopProcessGroup processIdPath
      | null processIdPath -> Left "test stopped-group command requires a process id path"
      | otherwise -> Right ()
    TestParentDeathProcessTree childPidPath
      | null childPidPath ->
          Left "test parent-death process-tree command requires a child pid path"
      | otherwise -> Right ()
    TestParentDeathStoppedProcessGroup processIdPath
      | null processIdPath ->
          Left "test parent-death stopped-group command requires a process id path"
      | otherwise -> Right ()
    TestSupervisorControlFailure -> Right ()
    TestDurableLeaseOrdering fileSyncPath directorySyncPath executedPath -> do
      validateAbsoluteTestPath
        "test durable-lease file-sync marker"
        fileSyncPath
      validateAbsoluteTestPath
        "test durable-lease directory-sync marker"
        directorySyncPath
      validateAbsoluteTestPath
        "test durable-lease executed marker"
        executedPath
    TestPrePreparedOwnerDeath readyPath executedPath -> do
      validateAbsoluteTestPath
        "test pre-prepared owner-death ready"
        readyPath
      validateAbsoluteTestPath
        "test pre-prepared owner-death executed"
        executedPath
    TestCustodyHandoffOwnerDeath readyPath executedPath -> do
      validateAbsoluteTestPath
        "test custody-handoff owner-death ready"
        readyPath
      validateAbsoluteTestPath
        "test custody-handoff owner-death executed"
        executedPath
    TestPreLeaseOwnerDeath readyPath executedPath
      | null readyPath ->
          Left "test pre-lease owner-death command requires a ready path"
      | null executedPath ->
          Left "test pre-lease owner-death command requires an executed path"
      | otherwise -> Right ()
    TestIncomingActivityRecovery readyPath releaseFifo executedPath -> do
      validateAbsoluteTestPath
        "test incoming-activity recovery ready"
        readyPath
      validateAbsoluteTestPath
        "test incoming-activity recovery release FIFO"
        releaseFifo
      validateAbsoluteTestPath
        "test incoming-activity recovery executed"
        executedPath
    TestIncomingActivityPrewriteRecovery readyPath releaseFifo executedPath -> do
      validateAbsoluteTestPath
        "test incoming-activity prewrite recovery ready"
        readyPath
      validateAbsoluteTestPath
        "test incoming-activity prewrite recovery release FIFO"
        releaseFifo
      validateAbsoluteTestPath
        "test incoming-activity prewrite recovery executed"
        executedPath
    TestIncomingActivityCancellation
      publicationReadyPath
      publicationReleaseFifo
      retirementReadyPath
      retirementReleaseFifo
      executedPath -> do
        validateAbsoluteTestPath
          "test incoming-activity cancellation publication ready"
          publicationReadyPath
        validateAbsoluteTestPath
          "test incoming-activity cancellation publication release"
          publicationReleaseFifo
        validateAbsoluteTestPath
          "test incoming-activity cancellation retirement ready"
          retirementReadyPath
        validateAbsoluteTestPath
          "test incoming-activity cancellation retirement release"
          retirementReleaseFifo
        validateAbsoluteTestPath
          "test incoming-activity cancellation executed"
          executedPath
    TestProtocolEvidence {} -> Right ()
    TestExitLeavingDescendant childPidPath
      | null childPidPath -> Left "test descendant command requires a child pid path"
      | otherwise -> Right ()
    TestTerminalFirstStoppedOwnerDeath childPidPath observationPath -> do
      validateAbsoluteTestPath
        "test terminal-first command descendant pid"
        childPidPath
      validateAbsoluteTestPath
        "test terminal-first command observation"
        observationPath

validateAbsoluteTestPath :: String -> FilePath -> Either String ()
validateAbsoluteTestPath label path
  | null path = Left (label <> " path cannot be empty")
  | not (isAbsolute path) = Left (label <> " path must be absolute")
  | otherwise = Right ()

testCommandOperation :: TestCommand -> TestOperation
testCommandOperation testCommand =
  case testCommand of
    TestEcho {} -> TestQuickOperation
    TestDelayedEcho {} -> TestQuickOperation
    TestExit {} -> TestQuickOperation
    TestSleep {} -> TestTimeoutOperation
    TestInvalidUtf8Stdout -> TestQuickOperation
    TestInvalidUtf8Stderr -> TestQuickOperation
    TestOutputOverflow -> TestQuickOperation
    TestIdempotentAbsence {} -> TestIdempotentOperation
    TestIdempotentFailure {} -> TestIdempotentOperation
    TestRetryThenSucceed {} -> TestRetryOperation
    TestRetryAlwaysFail {} -> TestRetryOperation
    TestRetryPastDeadline {} -> TestTotalDeadlineRetryOperation
    TestAcquisitionDeadline readyPath _ ->
      TestAcquisitionDeadlineOperation readyPath
    TestAnchorDeathBeforeSupervisorPublication readyPath ->
      TestAnchorDeathBeforeSupervisorPublicationOperation readyPath
    TestTargetSetupFailure ->
      TestTargetSetupFailureOperation
    TestSpawnProcessTree {} -> TestTimeoutOperation
    TestProtocolIsolationPeer readyPath _ ->
      TestProtocolIsolationPeerOperation readyPath
    TestDesignatedOwnerReaping readyPath _ evidencePrefix ->
      TestDesignatedOwnerReapingOperation readyPath evidencePrefix
    TestSynchronousExceptionProcessTree identityPath releaseFifo ->
      TestSynchronousExceptionOperation identityPath releaseFifo
    TestStopProcessGroup {} -> TestStoppedGroupOperation
    TestParentDeathProcessTree {} -> TestQuickOperation
    TestParentDeathStoppedProcessGroup {} -> TestQuickOperation
    TestSupervisorControlFailure -> TestSupervisorControlFailureOperation
    TestDurableLeaseOrdering fileSyncPath directorySyncPath _ ->
      TestDurableLeaseOrderingOperation fileSyncPath directorySyncPath
    TestPrePreparedOwnerDeath readyPath _ ->
      TestPrePreparedOwnerDeathOperation readyPath
    TestCustodyHandoffOwnerDeath readyPath _ ->
      TestCustodyHandoffOwnerDeathOperation readyPath
    TestPreLeaseOwnerDeath readyPath _ ->
      TestPreLeaseOwnerDeathOperation readyPath
    TestIncomingActivityRecovery readyPath releaseFifo _ ->
      TestIncomingActivityRecoveryOperation readyPath releaseFifo
    TestIncomingActivityPrewriteRecovery readyPath releaseFifo _ ->
      TestIncomingActivityPrewriteRecoveryOperation readyPath releaseFifo
    TestIncomingActivityCancellation
      publicationReadyPath
      publicationReleaseFifo
      retirementReadyPath
      retirementReleaseFifo
      _ ->
        TestIncomingActivityCancellationOperation
          publicationReadyPath
          publicationReleaseFifo
          retirementReadyPath
          retirementReleaseFifo
    TestProtocolEvidence evidenceCase ->
      TestProtocolEvidenceOperation evidenceCase
    TestExitLeavingDescendant {} -> TestQuickOperation
    TestTerminalFirstStoppedOwnerDeath _ observationPath ->
      TestTerminalFirstStoppedOwnerDeathOperation observationPath

testCommandPolicy :: TestOperation -> CommandPolicy
testCommandPolicy operation =
  case operation of
    TestQuickOperation -> seconds 30 NeverRetry FatalFailure
    TestTimeoutOperation -> seconds 1 NeverRetry FatalFailure
    TestStoppedGroupOperation -> seconds 5 NeverRetry FatalFailure
    TestRetryOperation ->
      seconds 30 (BoundedRetry 3 10000) TransientThenFatal
    TestTotalDeadlineRetryOperation ->
      seconds 1 (BoundedRetry 3 2000000) TransientThenFatal
    TestAcquisitionDeadlineOperation {} ->
      seconds 1 NeverRetry FatalFailure
    TestAnchorDeathBeforeSupervisorPublicationOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestTargetSetupFailureOperation ->
      seconds 30 NeverRetry FatalFailure
    TestProtocolIsolationPeerOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestDesignatedOwnerReapingOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestSynchronousExceptionOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestIdempotentOperation ->
      seconds 30 (BoundedRetry 3 10000) IdempotentAbsence
    TestSupervisorControlFailureOperation ->
      seconds 1 NeverRetry FatalFailure
    TestDurableLeaseOrderingOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestPrePreparedOwnerDeathOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestCustodyHandoffOwnerDeathOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestPreLeaseOwnerDeathOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestIncomingActivityRecoveryOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestIncomingActivityPrewriteRecoveryOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestIncomingActivityCancellationOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestProtocolEvidenceOperation {} ->
      seconds 30 NeverRetry FatalFailure
    TestTerminalFirstStoppedOwnerDeathOperation {} ->
      seconds 30 NeverRetry FatalFailure
  where
    seconds count =
      CommandPolicy
        (PositiveTimeout (count * 1000000))

supervisorControlFailureRequested :: CommandIdentity -> Bool
supervisorControlFailureRequested identity =
  case identity of
    TestCommandIdentity TestSupervisorControlFailureOperation -> True
    _ -> False

targetSetupFailureRequested :: CommandIdentity -> Bool
targetSetupFailureRequested identity =
  case identity of
    TestCommandIdentity TestTargetSetupFailureOperation -> True
    _ -> False

protocolEvidenceTestCase ::
  CommandIdentity ->
  Maybe TestProtocolEvidenceCase
protocolEvidenceTestCase identity =
  case identity of
    TestCommandIdentity (TestProtocolEvidenceOperation evidenceCase) ->
      Just evidenceCase
    _ -> Nothing

supervisorTerminalObservationPath :: CommandIdentity -> Maybe FilePath
supervisorTerminalObservationPath identity =
  case identity of
    TestCommandIdentity
      (TestTerminalFirstStoppedOwnerDeathOperation observationPath) ->
        Just observationPath
    _ -> Nothing

supervisorPrePreparedStopPath :: CommandIdentity -> Maybe FilePath
supervisorPrePreparedStopPath identity =
  case identity of
    TestCommandIdentity
      (TestPrePreparedOwnerDeathOperation readyPath) ->
        Just readyPath
    _ -> Nothing

supervisorCustodyHandoffStopPath :: CommandIdentity -> Maybe FilePath
supervisorCustodyHandoffStopPath identity =
  case identity of
    TestCommandIdentity
      (TestCustodyHandoffOwnerDeathOperation readyPath) ->
        Just readyPath
    _ -> Nothing

supervisorProtocolIsolationReadyPath ::
  CommandIdentity ->
  Maybe FilePath
supervisorProtocolIsolationReadyPath identity =
  case identity of
    TestCommandIdentity
      (TestProtocolIsolationPeerOperation readyPath) ->
        Just readyPath
    TestCommandIdentity
      (TestDesignatedOwnerReapingOperation readyPath _) ->
        Just readyPath
    _ -> Nothing

designatedOwnerReapEvidencePrefix ::
  CommandIdentity ->
  Maybe FilePath
designatedOwnerReapEvidencePrefix identity =
  case identity of
    TestCommandIdentity
      (TestDesignatedOwnerReapingOperation _ evidencePrefix) ->
        Just evidencePrefix
    _ -> Nothing

activityDurabilityMarkers ::
  CommandIdentity ->
  Maybe (FilePath, FilePath)
activityDurabilityMarkers identity =
  case identity of
    TestCommandIdentity
      (TestDurableLeaseOrderingOperation fileSyncPath directorySyncPath) ->
        Just (fileSyncPath, directorySyncPath)
    _ -> Nothing

acquisitionDeadlineTestReadyPath :: CommandIdentity -> Maybe FilePath
acquisitionDeadlineTestReadyPath identity =
  case identity of
    TestCommandIdentity (TestAcquisitionDeadlineOperation readyPath) ->
      Just readyPath
    _ -> Nothing

anchorPrePublicationDeathReadyPath ::
  CommandIdentity ->
  Maybe FilePath
anchorPrePublicationDeathReadyPath identity =
  case identity of
    TestCommandIdentity
      (TestAnchorDeathBeforeSupervisorPublicationOperation readyPath) ->
        Just readyPath
    _ -> Nothing

synchronousExceptionPaths ::
  CommandIdentity ->
  Maybe (FilePath, FilePath)
synchronousExceptionPaths identity =
  case identity of
    TestCommandIdentity
      (TestSynchronousExceptionOperation identityPath releaseFifo) ->
        Just (identityPath, releaseFifo)
    _ -> Nothing

synchronousExceptionReaderReadyPath :: FilePath -> FilePath
synchronousExceptionReaderReadyPath releaseFifo =
  releaseFifo <> ".reader-ready"

incomingActivityPublicationTestHooks ::
  CommandIdentity ->
  [Activity.ActivityPublicationTestHook]
incomingActivityPublicationTestHooks identity =
  case identity of
    TestCommandIdentity
      (TestIncomingActivityRecoveryOperation readyPath releaseFifo) ->
        [ Activity.planActivityPublicationTestHook
            readyPath
            releaseFifo
        ]
    TestCommandIdentity
      (TestIncomingActivityPrewriteRecoveryOperation readyPath releaseFifo) ->
        [ Activity.planActivityPrewriteTestHook
            readyPath
            releaseFifo
        ]
    TestCommandIdentity
      ( TestIncomingActivityCancellationOperation
          publicationReadyPath
          publicationReleaseFifo
          _
          _
        ) ->
        [ Activity.planActivityPublicationTestHook
            publicationReadyPath
            publicationReleaseFifo
        ]
    _ -> []

activityRetirementTestPaths ::
  CommandIdentity ->
  Maybe (FilePath, FilePath)
activityRetirementTestPaths identity =
  case identity of
    TestCommandIdentity
      ( TestIncomingActivityCancellationOperation
          _
          _
          retirementReadyPath
          retirementReleaseFifo
        ) ->
        Just (retirementReadyPath, retirementReleaseFifo)
    _ -> Nothing

renderTestCommand :: TestCommand -> RenderedProcess
renderTestCommand testCommand =
  case testCommand of
    TestEcho message ->
      fixedTestProcess testEchoExecutable [message] "" "test echo"
    TestDelayedEcho readyPath secondsToSleep message ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' ready > \"$1\"; \"$2\" \"$3\"; printf '%s\\n' \"$4\"",
          "infernix-test-delayed-echo",
          readyPath,
          testSleepExecutable,
          show secondsToSleep,
          message
        ]
        ""
        "test fixed delayed echo"
    TestExit exitCode ->
      fixedTestProcess
        testShellExecutable
        ["-c", "exit \"$1\"", "infernix-test-exit", show exitCode]
        ""
        "test fixed exit"
    TestSleep secondsToSleep ->
      fixedTestProcess
        testSleepExecutable
        [show secondsToSleep]
        ""
        "test fixed sleep"
    TestInvalidUtf8Stdout ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '\\300\\057'; printf '%s\\n' valid-stderr-evidence >&2"
        ]
        ""
        "test fixed invalid UTF-8 stdout"
    TestInvalidUtf8Stderr ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' valid-stdout-evidence; printf '\\300\\057' >&2"
        ]
        ""
        "test fixed invalid UTF-8 stderr"
    TestOutputOverflow ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' overflow-peer-stderr >&2; \"$1\" x | \"$2\" -c 16777217",
          "infernix-test-output-overflow",
          "/usr/bin/yes",
          "/usr/bin/head"
        ]
        ""
        "test fixed output overflow"
    TestIdempotentAbsence markerPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' attempt >> \"$1\"; printf '%s\\n' 'target does not exist' >&2; exit 1",
          "infernix-test-idempotent-absence",
          markerPath
        ]
        ""
        "test fixed idempotent absence"
    TestIdempotentFailure markerPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' attempt >> \"$1\"; printf '%s\\n' 'temporary delete failure' >&2; exit 7",
          "infernix-test-idempotent-failure",
          markerPath
        ]
        ""
        "test fixed idempotent failure"
    TestRetryThenSucceed markerPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "if [ -e \"$1\" ]; then exit 0; else : > \"$1\"; exit 7; fi",
          "infernix-test-retry",
          markerPath
        ]
        ""
        "test fixed retry"
    TestRetryAlwaysFail markerPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' attempt >> \"$1\"; exit 7",
          "infernix-test-exhausted-retry",
          markerPath
        ]
        ""
        "test fixed exhausted retry"
    TestRetryPastDeadline markerPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' attempt >> \"$1\"; exit 7",
          "infernix-test-total-deadline",
          markerPath
        ]
        ""
        "test fixed total-deadline retry"
    TestAcquisitionDeadline _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' executed > \"$1\"",
          "infernix-test-acquisition-deadline",
          executedPath
        ]
        ""
        "test fixed acquisition deadline"
    TestAnchorDeathBeforeSupervisorPublication _ ->
      fixedTestProcess
        testEchoExecutable
        ["unreachable"]
        ""
        "test fixed anchor pre-publication death"
    TestTargetSetupFailure ->
      fixedTestProcess
        testEchoExecutable
        ["unreachable"]
        ""
        "test fixed target setup failure"
    TestSpawnProcessTree childPidPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "\"$1\" 30 & child_pid=$!; printf '%s\\n' \"$child_pid\" > \"$2\"; wait \"$child_pid\"",
          "infernix-test-process-tree",
          testSleepExecutable,
          childPidPath
        ]
        ""
        "test fixed process tree"
    TestProtocolIsolationPeer _ releasePath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "\"$1\" \"$2\" >/dev/null; printf '%s\\n' released",
          "infernix-test-protocol-isolation-peer",
          "/bin/cat",
          releasePath
        ]
        ""
        "test fixed protocol-isolation peer"
    TestDesignatedOwnerReaping _ releasePath _ ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "\"$1\" \"$2\" >/dev/null; printf '%s\\n' released",
          "infernix-test-designated-owner-reaping",
          "/bin/cat",
          releasePath
        ]
        ""
        "test fixed designated-owner reaping"
    TestSynchronousExceptionProcessTree identityPath _ ->
      fixedTestProcess
        internalSelfExecutableSentinel
        [internalSynchronousTreeTargetMode, identityPath]
        ""
        "test exact synchronous-exception process tree"
    TestStopProcessGroup processIdPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' \"$$\" > \"$1\"; kill -STOP 0; exit 99",
          "infernix-test-stopped-process-group",
          processIdPath
        ]
        (replicate 1048576 'x')
        "test fixed stopped process group"
    TestParentDeathProcessTree childPidPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "\"$1\" 30 & child_pid=$!; printf '%s\\n' \"$child_pid\" > \"$2\"; wait \"$child_pid\"",
          "infernix-test-parent-death-process-tree",
          testSleepExecutable,
          childPidPath
        ]
        ""
        "test fixed parent-death process tree"
    TestParentDeathStoppedProcessGroup processIdPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' \"$$\" > \"$1\"; kill -STOP 0; exit 99",
          "infernix-test-parent-death-stopped-process-group",
          processIdPath
        ]
        ""
        "test fixed parent-death stopped process group"
    TestSupervisorControlFailure ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' supervisor-control-stdout; printf '%s\\n' supervisor-control-stderr >&2"
        ]
        ""
        "test fixed supervisor control failure"
    TestDurableLeaseOrdering fileSyncPath directorySyncPath executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "test -f \"$1\" && test -f \"$2\" || exit 96; printf '%s\\n' executed > \"$3\"",
          "infernix-test-durable-lease-ordering",
          fileSyncPath,
          directorySyncPath,
          executedPath
        ]
        ""
        "test fixed durable lease ordering"
    TestPrePreparedOwnerDeath _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' executed > \"$1\"",
          "infernix-test-pre-prepared-owner-death",
          executedPath
        ]
        ""
        "test fixed pre-prepared owner death"
    TestCustodyHandoffOwnerDeath _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' executed > \"$1\"",
          "infernix-test-custody-handoff-owner-death",
          executedPath
        ]
        ""
        "test fixed custody-handoff owner death"
    TestPreLeaseOwnerDeath _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' executed > \"$1\"",
          "infernix-test-pre-lease-owner-death",
          executedPath
        ]
        ""
        "test fixed pre-lease owner death"
    TestIncomingActivityRecovery _ _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' executed > \"$1\"",
          "infernix-test-incoming-activity-recovery",
          executedPath
        ]
        ""
        "test fixed incoming-activity recovery"
    TestIncomingActivityPrewriteRecovery _ _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\\n' executed > \"$1\"",
          "infernix-test-incoming-activity-prewrite-recovery",
          executedPath
        ]
        ""
        "test fixed incoming-activity prewrite recovery"
    TestIncomingActivityCancellation _ _ _ _ executedPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "printf '%s\n' executed > \"$1\"",
          "infernix-test-incoming-activity-cancellation",
          executedPath
        ]
        ""
        "test fixed incoming-activity cancellation"
    TestProtocolEvidence {} ->
      fixedTestProcess
        testEchoExecutable
        ["protocol-evidence"]
        ""
        "test fixed protocol evidence"
    TestExitLeavingDescendant childPidPath ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "\"$1\" 30 & child_pid=$!; printf '%s\\n' \"$child_pid\" > \"$2\"; exit 0",
          "infernix-test-exited-parent",
          testSleepExecutable,
          childPidPath
        ]
        ""
        "test fixed exited parent with descendant"
    TestTerminalFirstStoppedOwnerDeath childPidPath _ ->
      fixedTestProcess
        testShellExecutable
        [ "-c",
          "\"$1\" 30 & child_pid=$!; printf '%s\\n' \"$child_pid\" > \"$2\"; exit 0",
          "infernix-test-terminal-first-stopped-owner-death",
          testSleepExecutable,
          childPidPath
        ]
        ""
        "test fixed terminal-first stopped owner death"

fixedTestProcess ::
  FilePath ->
  [String] ->
  String ->
  String ->
  RenderedProcess
fixedTestProcess executable arguments input label =
  RenderedProcess
    { renderedExecutable = executable,
      renderedExecutableIdentity = Nothing,
      renderedArguments = arguments,
      renderedInput = input,
      renderedLabel = label,
      renderedWorkingDirectory = Nothing,
      renderedEnvironment = []
    }

testEchoExecutable :: FilePath
testEchoExecutable = "/bin/echo"

testShellExecutable :: FilePath
testShellExecutable = "/bin/sh"

testSleepExecutable :: FilePath
testSleepExecutable = "/bin/sleep"

runProvisioningFilesystemMutation ::
  SubprocessEnv ->
  Timeout ->
  ProvisioningFilesystemMutation ->
  IO ProvisioningFilesystemMutationOutcome
runProvisioningFilesystemMutation environment commandTimeout mutation =
  case commandTimeout of
    Timeout micros
      | micros <= 0 ->
          pure
            ( ProvisioningMutationRejectedSpec
                "provisioning mutation requires a positive total deadline"
            )
      | otherwise -> do
          compiled <-
            try @SomeException $ do
              executable <- getExecutablePath
              unless
                (isAbsolute executable && '\NUL' `notElem` executable)
                (ioError (userError "current executable path is not absolute"))
              let requestBytes =
                    LazyByteString.toStrict
                      ( Aeson.encode
                          (provisioningMutationWireRequest mutation)
                      )
              unless
                ( ByteString.length requestBytes
                    <= maximumProvisioningMutationRequestBytes
                )
                (ioError (userError "provisioning mutation request exceeds its bound"))
              either
                (ioError . userError)
                pure
                ( compileRenderedCommand
                    mutation
                    ProvisioningFilesystemMutationCommandIdentity
                    ( CommandPolicy
                        (PositiveTimeout micros)
                        NeverRetry
                        FatalFailure
                    )
                    environment
                    RenderedProcess
                      { renderedExecutable = executable,
                        renderedExecutableIdentity = Nothing,
                        renderedArguments =
                          [internalProvisioningMutationMode],
                        renderedInput =
                          ByteString8.unpack requestBytes,
                        renderedLabel =
                          "provisioning descriptor-custodied filesystem mutation",
                        renderedWorkingDirectory = Nothing,
                        renderedEnvironment = []
                      }
                )
          case compiled of
            Left failure ->
              case fromException failure :: Maybe SomeAsyncException of
                Just _ -> throwIO failure
                Nothing ->
                  pure
                    ( ProvisioningMutationKernelFailure
                        (Text.pack (displayException failure))
                    )
            Right bounded -> do
              outcome <- runBoundedCommand bounded
              pure (classifyProvisioningMutationCommandOutcome outcome)

-- | Fold the isolated mutation target's bounded-command outcome into the
-- provisioning mutation outcome the caller observes.
classifyProvisioningMutationCommandOutcome ::
  CommandOutcome ->
  ProvisioningFilesystemMutationOutcome
classifyProvisioningMutationCommandOutcome outcome =
  case outcome of
    CommandSucceeded output ->
      decodeProvisioningMutationHelperOutcome output
    CommandFailedFatal failure ->
      ProvisioningMutationKernelFailure
        ( "isolated mutation target failed unexpectedly: "
            <> Text.pack failure
        )
    CommandFailedKernel failure ->
      ProvisioningMutationKernelFailure (Text.pack failure)
    CommandTimedOut timedOut ->
      ProvisioningMutationTimedOut timedOut

decodeProvisioningMutationHelperOutcome ::
  String ->
  ProvisioningFilesystemMutationOutcome
decodeProvisioningMutationHelperOutcome output =
  case Aeson.eitherDecodeStrict' (ByteString8.pack output) of
    Left failure ->
      ProvisioningMutationKernelFailure
        ( "isolated mutation target returned an invalid result: "
            <> Text.pack failure
        )
    Right helperOutcome ->
      case helperOutcome of
        ProvisioningMutationHelperSucceeded ->
          ProvisioningMutationSucceeded
        ProvisioningMutationHelperRejected failure ->
          ProvisioningMutationRejectedSpec failure
        ProvisioningMutationHelperKernelFailure failure ->
          ProvisioningMutationKernelFailure failure

maximumProvisioningMutationRequestBytes :: Int
maximumProvisioningMutationRequestBytes = 65536

-- | Run a command under one required total 'Timeout'. The deadline encloses all
-- attempts and retry backoffs. Cleanup has its own bounded fail-closed phase, so
-- the deadline cannot interrupt process-group termination or lease retirement.
runBoundedCommand :: BoundedCommand command -> IO CommandOutcome
runBoundedCommand command
  -- A provisioning command carries exact executable authority in one of two
  -- forms. A target outside the mutation root keeps its resolved identity on
  -- the rendered command; a target *inside* that root — such as a candidate
  -- venv's own interpreter — has its authority moved by
  -- 'compileProvisioningCommandWithExecutableInMutationRoot' into the retained
  -- expectation, which the helper revalidates relative to the retained parent
  -- descriptor. Requiring only the first form rejects every in-root target.
  | ProvisioningCommandIdentity {} <- boundedCommandIdentity command,
    isNothing
      ( renderedExecutableIdentity
          (boundedRenderedCommand command)
      ),
    isNothing (boundedRetainedExecutableExpectation command) =
      pure
        ( CommandFailedKernel
            "runBoundedCommand: provisioning command has no exact executable authority"
        )
  | not rtsSupportsBoundThreads =
      pure
        ( CommandFailedKernel
            "runBoundedCommand: the subprocess supervisor requires a threaded RTS"
        )
  | otherwise = do
      startedAt <- getMonotonicTimeNSec
      let deadline = deadlineAfterMicros startedAt (timeoutMicros budget)
      registration <-
        try @SomeException
          (runActionBeforeDeadline deadline registerCurrentProcessIdentity)
      case registration of
        Left failure ->
          case fromException failure :: Maybe SomeAsyncException of
            Just _ -> throwIO failure
            Nothing
              | "attempt deadline expired"
                  `List.isInfixOf` displayException failure ->
                  pure (CommandTimedOut budget)
              | otherwise ->
                  pure
                    ( CommandFailedKernel
                        ( "runBoundedCommand: cannot register its owner identity: "
                            <> displayException failure
                        )
                    )
        Right _ ->
          runAttempts deadline (retryAttempts retryPolicy)
  where
    policy = boundedCommandPolicy command
    budget = commandPolicyTimeout policy
    identity = boundedCommandIdentity command
    retryPolicy = commandPolicyRetryPolicy policy
    failureClass = commandPolicyFailureClass policy
    runAttempts deadline remaining = do
      remainingMicros <- remainingDeadlineMicros deadline
      attempt <-
        if remainingMicros <= 0
          then pure AttemptTimedOut
          else runSupervisedAttempt command deadline
      case attempt of
        AttemptTimedOut ->
          pure (CommandTimedOut budget)
        AttemptKernelFailure message ->
          pure (CommandFailedKernel message)
        AttemptCompleted outcome _terminal _stdoutBytes _stderrBytes ->
          classifyAttempt deadline outcome remaining
    classifyAttempt deadline outcome remaining =
      case (outcome, retryPolicy, remaining) of
        (CommandFailedFatal message, _, _)
          | failureClass == IdempotentAbsence,
            isIdempotentFailure identity message ->
              pure (CommandSucceeded message)
        (CommandFailedFatal _, BoundedRetry _ backoffMicros, attemptsLeft)
          | attemptsLeft > 1
              && failureClass `elem` [TransientThenFatal, IdempotentAbsence] -> do
              remainingMicros <- remainingDeadlineMicros deadline
              if remainingMicros <= backoffMicros
                then do
                  delayForMicros remainingMicros
                  pure (CommandTimedOut budget)
                else do
                  delayForMicros backoffMicros
                  runAttempts deadline (attemptsLeft - 1)
        _ -> pure outcome

runBoundedCommandExactCapture ::
  BoundedCommand command ->
  IO NativeArtifactCommandOutcome
runBoundedCommandExactCapture command
  | Just audit <- sealedRunLoaderAuditFor (boundedCommandIdentity command),
    Just leaseExpectation <- boundedArtifactGenerationLeaseExpectation command,
    -- The relative executable is present for an installed artifact and absent
    -- for an image target, which executes an absolute path the immutable image
    -- owns. Both are closed target shapes; what authorizes the run is the
    -- retained generation root, which is required either way.
    Just
      ( ProvisioningMutationWorkingDirectory
          retainedRoot
          _
          _
        ) <-
      boundedProvisioningMutationWorkingDirectory command,
    NeverRetry <-
      commandPolicyRetryPolicy (boundedCommandPolicy command) =
      if not rtsSupportsBoundThreads
        then
          pure
            ( NativeArtifactCommandKernelFailure
                "bounded exact-capture command requires a threaded RTS"
            )
        else do
          startedAt <- getMonotonicTimeNSec
          let budget = commandPolicyTimeout (boundedCommandPolicy command)
              deadline = deadlineAfterMicros startedAt (timeoutMicros budget)
          registration <-
            try @SomeException
              (runActionBeforeDeadline deadline registerCurrentProcessIdentity)
          case registration of
            Left failure ->
              case fromException failure :: Maybe SomeAsyncException of
                Just _ -> throwIO failure
                Nothing
                  | "attempt deadline expired"
                      `List.isInfixOf` displayException failure ->
                      pure (NativeArtifactCommandTimedOut budget)
                  | otherwise ->
                      pure
                        ( NativeArtifactCommandKernelFailure
                            (Text.pack (displayException failure))
                        )
            Right _ -> do
              remainingMicros <- remainingDeadlineMicros deadline
              attempt <-
                if remainingMicros <= 0
                  then pure AttemptTimedOut
                  else runSupervisedAttempt command deadline
              case sealedRunOwnedRoots leaseExpectation retainedRoot of
                Left failure ->
                  pure (NativeArtifactCommandKernelFailure (Text.pack failure))
                Right ownedRoots ->
                  pure
                    ( classifyExactCaptureAttempt
                        budget
                        audit
                        ownedRoots
                        attempt
                    )
  | otherwise =
      pure
        ( NativeArtifactCommandKernelFailure
            "bounded exact-capture command lacks closed generation and relative-target authority"
        )

-- | Fold one exact-capture supervised attempt into its typed native-artifact
-- outcome. A clean target exit is admitted only once the retained generation's
-- loader provenance validates.
classifyExactCaptureAttempt ::
  Timeout ->
  SealedRunLoaderAudit ->
  [FilePath] ->
  AttemptOutcome ->
  NativeArtifactCommandOutcome
classifyExactCaptureAttempt budget audit ownedRoots attempt =
  case attempt of
    AttemptTimedOut ->
      NativeArtifactCommandTimedOut budget
    AttemptKernelFailure failure ->
      NativeArtifactCommandKernelFailure (Text.pack failure)
    AttemptCompleted classified terminal stdoutBytes stderrBytes ->
      case classified of
        CommandFailedKernel failure ->
          NativeArtifactCommandKernelFailure (Text.pack failure)
        CommandTimedOut timedOut ->
          NativeArtifactCommandTimedOut timedOut
        _ ->
          classifyExactCaptureTerminal
            audit
            ownedRoots
            terminal
            stdoutBytes
            stderrBytes

-- | Which loader an exact-capture smoke's own run is audited against.
--
-- Selected from the command's closed provisioning operation, so a smoke cannot
-- be compiled with the wrong audit: an Apple installed runner is audited
-- against @dyld@ and a Linux native artifact against @ld.so@.
data SealedRunLoaderAudit
  = DyldSealedRunAudit
  | ElfSealedRunAudit
  deriving (Eq, Show)

sealedRunLoaderAuditFor ::
  CommandIdentity ->
  Maybe SealedRunLoaderAudit
sealedRunLoaderAuditFor identity =
  case identity of
    ClosedArtifactSmokeCommandIdentity
      (Provisioning.InstalledRunnerSmokeOperation _) ->
        Just DyldSealedRunAudit
    ClosedArtifactSmokeCommandIdentity
      (Provisioning.InstalledPythonSourceIsolationSmokeOperation _) ->
        Just DyldSealedRunAudit
    ClosedArtifactSmokeCommandIdentity
      (Provisioning.LinuxNativeArtifactSmokeOperation _ _) ->
        Just ElfSealedRunAudit
    _ -> Nothing

classifyExactCaptureTerminal ::
  SealedRunLoaderAudit ->
  [FilePath] ->
  TargetTerminal ->
  ByteString.ByteString ->
  ByteString.ByteString ->
  NativeArtifactCommandOutcome
classifyExactCaptureTerminal audit ownedRoots terminal stdoutBytes stderrBytes =
  case terminal of
    TargetExited 0 ->
      case auditSealedRun
        audit
        ownedRoots
        stderrBytes of
        Left failure ->
          NativeArtifactCommandKernelFailure failure
        Right applicationOutput ->
          -- A runner that reports through stderr leaves stdout empty. The
          -- validated output is its own diagnostics with every loader frame
          -- removed, never the raw stderr.
          NativeArtifactCommandExited
            ExitSuccess
            ( if ByteString.null (trimCapturedBytes stdoutBytes)
                then applicationOutput
                else stdoutBytes
            )
            stderrBytes
    TargetExited exitCode ->
      NativeArtifactCommandExited
        (ExitFailure exitCode)
        stdoutBytes
        stderrBytes
    TargetSignaled signal coreDumped ->
      NativeArtifactCommandSignaled
        signal
        coreDumped
        stdoutBytes
        stderrBytes
    TargetKernelFailure failure ->
      NativeArtifactCommandKernelFailure (Text.pack failure)

remainingDeadlineMicros :: Word64 -> IO Int
remainingDeadlineMicros deadline = do
  now <- getMonotonicTimeNSec
  pure
    ( if now >= deadline
        then 0
        else
          fromIntegral
            (min (fromIntegral (maxBound :: Int)) ((deadline - now) `div` 1000))
    )

delayForMicros :: Int -> IO ()
delayForMicros delayMicros
  | delayMicros <= 0 = pure ()
  | otherwise = do
      delayVar <- newEmptyMVar
      void (timeout delayMicros (takeMVar delayVar))

deadlineAfterMicros :: Word64 -> Int -> Word64
deadlineAfterMicros startedAt microseconds =
  fromInteger
    ( min
        (toInteger (maxBound :: Word64))
        (toInteger startedAt + toInteger microseconds * 1000)
    )

isIdempotentFailure :: CommandIdentity -> String -> Bool
isIdempotentFailure identity message =
  case identity of
    ProductionCommandIdentity KindDeleteOperation ->
      containsAny
        [ "no kind clusters found",
          "could not find a cluster with the name"
        ]
    ProductionCommandIdentity KubectlDeleteOperation ->
      contains "error from server (notfound):"
        && contains " not found"
    ProductionCommandIdentity DockerNetworkOperation ->
      contains "already connected to network"
        || (contains "endpoint with name" && contains "already exists in network")
    ProductionCommandIdentity ImagePublicationRemoveOperation ->
      contains "no such image:"
    TestCommandIdentity TestIdempotentOperation ->
      contains "target does not exist"
    _ -> False
  where
    normalizedMessage = map toLower message
    contains needle = needle `List.isInfixOf` normalizedMessage
    containsAny = any (`List.isInfixOf` normalizedMessage)

retryAttempts :: RetryPolicy -> Int
retryAttempts NeverRetry = 1
retryAttempts (BoundedRetry attempts _) = attempts

data ActivityProcessIdentity = ActivityProcessIdentity
  { activityProcessId :: !Integer,
    activityProcessGroup :: !Integer,
    activityProcessBirthIdentity :: !ProcessBirthIdentity
  }
  deriving (Eq, Show)

data ProvisionalProcessIdentity = ProvisionalProcessIdentity
  { provisionalProcessId :: !Integer,
    provisionalProcessGroup :: !Integer,
    provisionalBirthIdentity :: !ProcessBirthIdentity
  }
  deriving (Eq, Show)

provisionalFromActivityIdentity ::
  ActivityProcessIdentity ->
  ProvisionalProcessIdentity
provisionalFromActivityIdentity identity =
  ProvisionalProcessIdentity
    { provisionalProcessId = activityProcessId identity,
      provisionalProcessGroup = activityProcessGroup identity,
      provisionalBirthIdentity = activityProcessBirthIdentity identity
    }

data CommandActivityIdentities
  = CommandActivityCommandOnly
  | CommandActivityWithSupervisor !ActivityProcessIdentity
  | CommandActivityDurable
      !ActivityProcessIdentity
      !ActivityProcessIdentity
      !ActivityProcessIdentity
  deriving (Eq, Show)

data CommandActivityLeaseDocument = CommandActivityLeaseDocument
  { activityOwnerProcessGroup :: !Integer,
    activityCommandIdentity :: !ActivityProcessIdentity,
    activityIdentities :: !CommandActivityIdentities
  }
  deriving (Eq, Show)

activityOwnerIdentity ::
  CommandActivityLeaseDocument ->
  Maybe ActivityProcessIdentity
activityOwnerIdentity activity =
  case activityIdentities activity of
    CommandActivityDurable ownerIdentity _ _ -> Just ownerIdentity
    _ -> Nothing

activitySupervisorIdentity ::
  CommandActivityLeaseDocument ->
  Maybe ActivityProcessIdentity
activitySupervisorIdentity activity =
  case activityIdentities activity of
    CommandActivityCommandOnly -> Nothing
    CommandActivityWithSupervisor supervisorIdentity ->
      Just supervisorIdentity
    CommandActivityDurable _ supervisorIdentity _ ->
      Just supervisorIdentity

activityTargetGroupLeaderIdentity ::
  CommandActivityLeaseDocument ->
  Maybe ActivityProcessIdentity
activityTargetGroupLeaderIdentity activity =
  case activityIdentities activity of
    CommandActivityDurable _ _ targetIdentity -> Just targetIdentity
    _ -> Nothing

instance Aeson.ToJSON CommandActivityLeaseDocument where
  toJSON activity =
    case activityIdentities activity of
      CommandActivityCommandOnly ->
        Aeson.object
          (activityJsonFields 1 activity)
      CommandActivityWithSupervisor supervisorIdentity ->
        Aeson.object
          ( activityJsonFields 2 activity
              <> supervisorIdentityJsonFields supervisorIdentity
          )
      CommandActivityDurable ownerIdentity supervisorIdentity targetIdentity ->
        Aeson.object
          ( activityJsonFields 3 activity
              <> ownerIdentityJsonFields ownerIdentity
              <> supervisorIdentityJsonFields supervisorIdentity
              <> [ "targetGroupLeaderProcessId"
                     Aeson..= activityProcessId targetIdentity,
                   "targetGroup"
                     Aeson..= activityProcessGroup targetIdentity,
                   "targetGroupLeaderBirthIdentity"
                     Aeson..= renderProcessBirthIdentity
                       (activityProcessBirthIdentity targetIdentity)
                 ]
          )

instance Aeson.FromJSON CommandActivityLeaseDocument where
  parseJSON =
    Aeson.withObject "CommandActivityLeaseDocument" $ \value -> do
      version <- value Aeson..: "version"
      ownerProcessGroup <- value Aeson..: "ownerProcessGroup"
      commandIdentity <-
        parseActivityProcessIdentity
          value
          "commandProcessId"
          "commandProcessGroup"
          "commandBirthIdentity"
      identities <-
        case version :: Int of
          1 -> pure CommandActivityCommandOnly
          2 -> do
            decodedSupervisor <- parseSupervisorIdentity value
            pure (CommandActivityWithSupervisor decodedSupervisor)
          3 -> do
            decodedOwner <-
              parseActivityIdentity
                value
                "ownerProcessId"
                "ownerProcessGroup"
                "ownerBirthIdentity"
            decodedSupervisor <- parseSupervisorIdentity value
            decodedTarget <-
              parseActivityProcessIdentity
                value
                "targetGroupLeaderProcessId"
                "targetGroup"
                "targetGroupLeaderBirthIdentity"
            pure
              ( CommandActivityDurable
                  decodedOwner
                  decodedSupervisor
                  decodedTarget
              )
          _ -> fail "unsupported bounded-command activity lease version"
      let activity =
            CommandActivityLeaseDocument
              { activityOwnerProcessGroup = ownerProcessGroup,
                activityCommandIdentity = commandIdentity,
                activityIdentities = identities
              }
      either fail (const (pure activity)) (validateCommandActivityTopology activity)

validateCommandActivityTopology ::
  CommandActivityLeaseDocument ->
  Either String ()
validateCommandActivityTopology activity = do
  let ownerProcessGroup = activityOwnerProcessGroup activity
      ownerIdentities =
        case activityOwnerIdentity activity of
          Nothing -> []
          Just ownerIdentity -> [ownerIdentity]
      supervisorIdentities =
        maybe [] pure (activitySupervisorIdentity activity)
      targetIdentities =
        maybe [] pure (activityTargetGroupLeaderIdentity activity)
      helperIdentities =
        [activityCommandIdentity activity]
          <> supervisorIdentities
          <> targetIdentities
      processIds =
        map activityProcessId (ownerIdentities <> helperIdentities)
      helperProcessGroups =
        map activityProcessGroup helperIdentities
  unlessEither
    (validActivityProcessId ownerProcessGroup)
    "invalid bounded-command activity owner process group"
  unlessEither
    ( maybe
        True
        ((== ownerProcessGroup) . activityProcessGroup)
        (activityOwnerIdentity activity)
    )
    "bounded-command activity owner identity does not match its process group"
  unlessEither
    (length processIds == length (List.nub processIds))
    "bounded-command activity process identities are not distinct"
  unlessEither
    (length helperProcessGroups == length (List.nub helperProcessGroups))
    "bounded-command activity helper process groups are not distinct"
  unlessEither
    (ownerProcessGroup `notElem` helperProcessGroups)
    "bounded-command activity helper process group collides with its owner"
  where
    unlessEither predicate failure
      | predicate = Right ()
      | otherwise = Left failure

parseSupervisorIdentity ::
  Object ->
  Parser ActivityProcessIdentity
parseSupervisorIdentity value =
  parseActivityProcessIdentity
    value
    "watchdogProcessId"
    "watchdogProcessGroup"
    "watchdogBirthIdentity"

ownerIdentityJsonFields ::
  ActivityProcessIdentity ->
  [Pair]
ownerIdentityJsonFields ownerIdentity =
  [ "ownerProcessId"
      Aeson..= activityProcessId ownerIdentity,
    "ownerBirthIdentity"
      Aeson..= renderProcessBirthIdentity
        (activityProcessBirthIdentity ownerIdentity)
  ]

supervisorIdentityJsonFields ::
  ActivityProcessIdentity ->
  [Pair]
supervisorIdentityJsonFields supervisorIdentity =
  [ "watchdogProcessId"
      Aeson..= activityProcessId supervisorIdentity,
    "watchdogProcessGroup"
      Aeson..= activityProcessGroup supervisorIdentity,
    "watchdogBirthIdentity"
      Aeson..= renderProcessBirthIdentity
        (activityProcessBirthIdentity supervisorIdentity)
  ]

activityJsonFields ::
  Int ->
  CommandActivityLeaseDocument ->
  [Pair]
activityJsonFields version activity =
  [ "version" Aeson..= version,
    "ownerProcessGroup" Aeson..= activityOwnerProcessGroup activity,
    "commandProcessId" Aeson..= activityProcessId commandIdentity,
    "commandProcessGroup" Aeson..= activityProcessGroup commandIdentity,
    "commandBirthIdentity"
      Aeson..= renderProcessBirthIdentity
        (activityProcessBirthIdentity commandIdentity)
  ]
  where
    commandIdentity = activityCommandIdentity activity

parseActivityProcessIdentity ::
  Object ->
  Key ->
  Key ->
  Key ->
  Parser ActivityProcessIdentity
parseActivityProcessIdentity value processIdField processGroupField birthIdentityField = do
  identity <-
    parseActivityIdentity
      value
      processIdField
      processGroupField
      birthIdentityField
  if activityProcessGroup identity == activityProcessId identity
    then pure identity
    else fail "bounded-command activity identity is not a process-group leader"

parseActivityIdentity ::
  Object ->
  Key ->
  Key ->
  Key ->
  Parser ActivityProcessIdentity
parseActivityIdentity value processIdField processGroupField birthIdentityField = do
  processId <- value Aeson..: processIdField
  processGroup <- value Aeson..: processGroupField
  birthIdentityText <- value Aeson..: birthIdentityField
  birthIdentity <-
    maybe
      (fail "invalid bounded-command activity birth identity")
      pure
      (parseProcessBirthIdentity birthIdentityText)
  if validActivityProcessId processId
    && validActivityProcessId processGroup
    then
      pure
        ActivityProcessIdentity
          { activityProcessId = processId,
            activityProcessGroup = processGroup,
            activityProcessBirthIdentity = birthIdentity
          }
    else fail "invalid bounded-command activity process identity"

data PublishedCommandActivity = PublishedCommandActivity
  { publishedActivityDocument :: !CommandActivityLeaseDocument,
    publishedActivityPath :: !FilePath,
    publishedActivityIncomingPath :: !FilePath
  }

-- | Evidence that every published bounded-command activity for one owner
-- process group has reached an absent command process group. The constructor is
-- hidden; cluster recovery must obtain this through
-- 'proveBoundedCommandActivitiesQuiescent'.
newtype BoundedCommandActivitiesQuiescent
  = BoundedCommandActivitiesQuiescent Integer

boundedCommandActivitiesOwnerProcessGroup ::
  BoundedCommandActivitiesQuiescent ->
  Integer
boundedCommandActivitiesOwnerProcessGroup
  (BoundedCommandActivitiesQuiescent ownerProcessGroup) =
    ownerProcessGroup

-- | Opaque evidence that every activity whose exact owner was already dead
-- has been recovered and retired beneath one typed runtime root. Exact-live
-- unrelated owners are deliberately left alone. A materialization writer
-- obtains this only after taking the global exclusive engine lock, which
-- prevents a relevant installed-runtime reader from racing this preflight.
newtype AbandonedActivitiesRecovered
  = AbandonedActivitiesRecovered FilePath

data TrackedProcess = TrackedProcess
  { trackedProcessId :: !ProcessID,
    trackedProcessGroup :: !Integer,
    trackedProcessIdentity :: !ActivityProcessIdentity,
    trackedProcessRegistration ::
      !(MVar (Maybe ProcessIdentityInternal.RegisteredProcessIdentity)),
    trackedProcessStatus :: !(MVar (Maybe ProcessStatus)),
    trackedProcessExecReport :: !(MVar (Maybe ByteString.ByteString))
  }

data AttemptOutcome
  = AttemptTimedOut
  | AttemptKernelFailure !String
  | AttemptCompleted
      !CommandOutcome
      !TargetTerminal
      !ByteString.ByteString
      !ByteString.ByteString
  deriving (Show)

data SynchronousProtocolTestFailure
  = SynchronousProtocolTestFailure
  deriving (Show)

instance Exception SynchronousProtocolTestFailure

writeExecFailureReport :: Fd -> IOException -> IO ()
writeExecFailureReport outputFd failure =
  -- Keep the complete provenance report below POSIX's minimum PIPE_BUF so a
  -- live supervisor observes either the whole frame or a write failure.
  writeFdFullyBlocking
    outputFd
    ( ByteString8.pack
        ("exec-failed\n" <> take 240 (displayException failure))
    )

writeFdFullyBlocking :: Fd -> ByteString8.ByteString -> IO ()
writeFdFullyBlocking outputFd = writeBytes
  where
    writeBytes contents
      | ByteString8.null contents = pure ()
      | otherwise = do
          writeResult <-
            try @IOException
              (PosixByteString.fdWrite outputFd contents)
          case writeResult of
            Left err
              | ioeGetErrorType err == Interrupted -> writeBytes contents
              | otherwise -> ioError err
            Right written ->
              writeBytes (ByteString8.drop (fromIntegral written) contents)

writeFdFully :: Fd -> ByteString8.ByteString -> IO ()
writeFdFully outputFd = writeBytes
  where
    writeBytes contents
      | ByteString8.null contents = pure ()
      | otherwise = do
          threadWaitWrite outputFd
          writeResult <-
            try @IOException
              (PosixByteString.fdWrite outputFd contents)
          case writeResult of
            Left err
              | retryableDescriptorError err -> writeBytes contents
              | otherwise -> ioError err
            Right written ->
              writeBytes (ByteString8.drop (fromIntegral written) contents)

runPreLeaseTestHook ::
  ActivityProcessIdentity ->
  ActivityProcessIdentity ->
  ActivityProcessIdentity ->
  CommandIdentity ->
  IO ()
runPreLeaseTestHook anchorIdentity supervisorIdentity pinIdentity identity =
  case identity of
    TestCommandIdentity (TestPreLeaseOwnerDeathOperation readyPath) -> do
      ByteString8.writeFile
        readyPath
        ( ByteString8.pack
            ( show (activityProcessId anchorIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity anchorIdentity)
                <> "\n"
                <> show (activityProcessId supervisorIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity supervisorIdentity)
                <> "\n"
                <> show (activityProcessId pinIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity pinIdentity)
                <> "\n"
            )
        )
      ownerDeathGate <- newEmptyMVar :: IO (MVar ())
      takeMVar ownerDeathGate
    _ -> pure ()

validActivityProcessId :: Integer -> Bool
validActivityProcessId processId =
  processId > 0 && processId <= 2147483647

commandActivityRoot :: FilePath -> FilePath
commandActivityRoot activeRuntimeRoot =
  activeRuntimeRoot </> "bounded-command-activity"

incomingActivityRecoveryPrefix :: String
incomingActivityRecoveryPrefix = ".incoming-activity-v3."

incomingActivityDistinctRecoveryPrefix :: String
incomingActivityDistinctRecoveryPrefix = ".incoming-activity-v4.i"

incomingCommandActivityFileName ::
  CommandActivityLeaseDocument ->
  Either String FilePath
incomingCommandActivityFileName activity = do
  validateCommandActivityTopology activity
  ownerIdentity <-
    maybe
      (Left "bounded-command incoming intent requires an exact owner identity")
      Right
      (activityOwnerIdentity activity)
  supervisorIdentity <-
    maybe
      (Left "bounded-command incoming intent requires an exact supervisor identity")
      Right
      (activitySupervisorIdentity activity)
  pinIdentity <-
    maybe
      (Left "bounded-command incoming intent requires an exact target-group identity")
      Right
      (activityTargetGroupLeaderIdentity activity)
  let anchorIdentity = activityCommandIdentity activity
      identities =
        [ ownerIdentity,
          anchorIdentity,
          supervisorIdentity,
          pinIdentity
        ]
      bootIdentities =
        map
          ( processBirthBootIdentity
              . activityProcessBirthIdentity
          )
          identities
      leaderIdentities =
        [anchorIdentity, supervisorIdentity, pinIdentity]
  when
    ( any
        (\identity -> activityProcessId identity /= activityProcessGroup identity)
        leaderIdentities
    )
    $ Left "bounded-command incoming intent identities are structurally invalid"
  case bootIdentities of
    commonBoot : remainingBoots
      | all (== commonBoot) remainingBoots,
        not (null commonBoot),
        '.' `notElem` commonBoot ->
          renderCommonBootIntent
            commonBoot
            ownerIdentity
            anchorIdentity
            supervisorIdentity
            pinIdentity
    _ ->
      renderDistinctBootIntent
        ownerIdentity
        anchorIdentity
        supervisorIdentity
        pinIdentity
  where
    renderHex value = showHex value ""
    renderCommonBootIntent
      commonBoot
      ownerIdentity
      anchorIdentity
      supervisorIdentity
      pinIdentity =
        let encoded =
              incomingActivityRecoveryPrefix
                <> List.intercalate
                  "."
                  [ commonBoot,
                    renderHex (activityProcessId ownerIdentity),
                    renderHex (activityProcessGroup ownerIdentity),
                    renderHex
                      ( processBirthStartTime
                          (activityProcessBirthIdentity ownerIdentity)
                      ),
                    renderHex (activityProcessId anchorIdentity),
                    renderHex
                      ( processBirthStartTime
                          (activityProcessBirthIdentity anchorIdentity)
                      ),
                    renderHex (activityProcessId supervisorIdentity),
                    renderHex
                      ( processBirthStartTime
                          (activityProcessBirthIdentity supervisorIdentity)
                      ),
                    renderHex (activityProcessId pinIdentity),
                    renderHex
                      ( processBirthStartTime
                          (activityProcessBirthIdentity pinIdentity)
                      )
                  ]
         in if length encoded <= 255
              then Right encoded
              else Left "bounded-command incoming intent filename exceeds its size limit"

    renderDistinctBootIntent
      ownerIdentity
      anchorIdentity
      supervisorIdentity
      pinIdentity = do
        ownerFields <- renderOwnerFields ownerIdentity
        anchorFields <- renderHelperFields anchorIdentity
        supervisorFields <- renderHelperFields supervisorIdentity
        pinFields <- renderHelperFields pinIdentity
        let encoded =
              incomingActivityDistinctRecoveryPrefix
                <> ownerFields
                <> anchorFields
                <> supervisorFields
                <> pinFields
        if length encoded == 255
          then Right encoded
          else Left "bounded-command distinct-token incoming intent has an invalid size"

    renderOwnerFields identity =
      (<>)
        <$> renderBootToken identity
        <*> ( (<>)
                <$> renderFixedHex 8 (activityProcessId identity)
                <*> ( (<>)
                        <$> renderFixedHex 8 (activityProcessGroup identity)
                        <*> renderFixedHex
                          16
                          ( processBirthStartTime
                              (activityProcessBirthIdentity identity)
                          )
                    )
            )

    renderHelperFields identity =
      (<>)
        <$> renderBootToken identity
        <*> ( (<>)
                <$> renderFixedHex 8 (activityProcessId identity)
                <*> renderFixedHex
                  16
                  ( processBirthStartTime
                      (activityProcessBirthIdentity identity)
                  )
            )

    renderBootToken identity =
      let bootIdentity =
            processBirthBootIdentity
              (activityProcessBirthIdentity identity)
       in if length bootIdentity == 32
            && all isHexDigit bootIdentity
            then Right (map toLower bootIdentity)
            else
              Left
                "bounded-command distinct-token incoming intent requires a 128-bit hexadecimal token"

    renderFixedHex width value =
      let rendered = showHex value ""
       in if length rendered <= width
            then Right (replicate (width - length rendered) '0' <> rendered)
            else Left "bounded-command incoming intent field exceeds its fixed width"

commandActivityFromIncomingFileName ::
  FilePath ->
  Either String CommandActivityLeaseDocument
commandActivityFromIncomingFileName entry =
  case List.stripPrefix incomingActivityRecoveryPrefix entry of
    Just encoded -> parseCommonBootIntent encoded
    Nothing ->
      case List.stripPrefix incomingActivityDistinctRecoveryPrefix entry of
        Just encoded -> parseDistinctBootIntent encoded
        Nothing ->
          Left "bounded-command incoming intent has an unsupported filename"
  where
    parseCommonBootIntent encoded = do
      ( bootIdentity,
        ownerProcessId,
        ownerProcessGroup,
        ownerStartTime,
        anchorProcessId,
        anchorStartTime,
        supervisorProcessId,
        supervisorStartTime,
        pinProcessId,
        pinStartTime
        ) <-
        case splitOnDot encoded of
          [ boot,
            ownerPid,
            ownerGroup,
            ownerStart,
            anchorPid,
            anchorStart,
            supervisorPid,
            supervisorStart,
            pinPid,
            pinStart
            ] ->
              (,,,,,,,,,)
                boot
                <$> parsePositiveHex "owner pid" ownerPid
                <*> parsePositiveHex "owner group" ownerGroup
                <*> parsePositiveHex "owner start" ownerStart
                <*> parsePositiveHex "anchor pid" anchorPid
                <*> parsePositiveHex "anchor start" anchorStart
                <*> parsePositiveHex "supervisor pid" supervisorPid
                <*> parsePositiveHex "supervisor start" supervisorStart
                <*> parsePositiveHex "pin pid" pinPid
                <*> parsePositiveHex "pin start" pinStart
          _ -> Left "bounded-command incoming intent filename is malformed"
      buildIncomingActivity
        bootIdentity
        ownerProcessId
        ownerProcessGroup
        ownerStartTime
        bootIdentity
        anchorProcessId
        anchorStartTime
        bootIdentity
        supervisorProcessId
        supervisorStartTime
        bootIdentity
        pinProcessId
        pinStartTime

    parseDistinctBootIntent encoded = do
      (ownerBoot, ownerFields) <- takeFixedField 32 "owner token" encoded
      (ownerPid, ownerGroupFields) <- takeFixedField 8 "owner pid" ownerFields
      (ownerGroup, ownerStartFields) <-
        takeFixedField 8 "owner group" ownerGroupFields
      (ownerStart, anchorFields) <-
        takeFixedField 16 "owner start" ownerStartFields
      (anchorBoot, anchorPidFields) <-
        takeFixedField 32 "anchor token" anchorFields
      (anchorPid, anchorStartFields) <-
        takeFixedField 8 "anchor pid" anchorPidFields
      (anchorStart, supervisorFields) <-
        takeFixedField 16 "anchor start" anchorStartFields
      (supervisorBoot, supervisorPidFields) <-
        takeFixedField 32 "supervisor token" supervisorFields
      (supervisorPid, supervisorStartFields) <-
        takeFixedField 8 "supervisor pid" supervisorPidFields
      (supervisorStart, pinFields) <-
        takeFixedField 16 "supervisor start" supervisorStartFields
      (pinBoot, pinPidFields) <-
        takeFixedField 32 "pin token" pinFields
      (pinPid, pinStartFields) <-
        takeFixedField 8 "pin pid" pinPidFields
      (pinStart, remainder) <-
        takeFixedField 16 "pin start" pinStartFields
      unlessEither
        (null remainder)
        "bounded-command distinct-token incoming intent has trailing data"
      ownerProcessId <- parsePositiveHex "owner pid" ownerPid
      ownerProcessGroup <- parsePositiveHex "owner group" ownerGroup
      ownerStartTime <- parsePositiveHex "owner start" ownerStart
      anchorProcessId <- parsePositiveHex "anchor pid" anchorPid
      anchorStartTime <- parsePositiveHex "anchor start" anchorStart
      supervisorProcessId <-
        parsePositiveHex "supervisor pid" supervisorPid
      supervisorStartTime <-
        parsePositiveHex "supervisor start" supervisorStart
      pinProcessId <- parsePositiveHex "pin pid" pinPid
      pinStartTime <- parsePositiveHex "pin start" pinStart
      buildIncomingActivity
        ownerBoot
        ownerProcessId
        ownerProcessGroup
        ownerStartTime
        anchorBoot
        anchorProcessId
        anchorStartTime
        supervisorBoot
        supervisorProcessId
        supervisorStartTime
        pinBoot
        pinProcessId
        pinStartTime

    buildIncomingActivity
      ownerBoot
      ownerProcessId
      ownerProcessGroup
      ownerStartTime
      anchorBoot
      anchorProcessId
      anchorStartTime
      supervisorBoot
      supervisorProcessId
      supervisorStartTime
      pinBoot
      pinProcessId
      pinStartTime = do
        ownerBirthIdentity <-
          parseIncomingBirthIdentity ownerBoot ownerStartTime
        anchorBirthIdentity <-
          parseIncomingBirthIdentity anchorBoot anchorStartTime
        supervisorBirthIdentity <-
          parseIncomingBirthIdentity supervisorBoot supervisorStartTime
        pinBirthIdentity <-
          parseIncomingBirthIdentity pinBoot pinStartTime
        let ownerIdentity =
              ActivityProcessIdentity
                ownerProcessId
                ownerProcessGroup
                ownerBirthIdentity
            anchorIdentity =
              ActivityProcessIdentity
                anchorProcessId
                anchorProcessId
                anchorBirthIdentity
            supervisorIdentity =
              ActivityProcessIdentity
                supervisorProcessId
                supervisorProcessId
                supervisorBirthIdentity
            pinIdentity =
              ActivityProcessIdentity
                pinProcessId
                pinProcessId
                pinBirthIdentity
            processIds =
              [ ownerProcessId,
                anchorProcessId,
                supervisorProcessId,
                pinProcessId
              ]
            activity =
              CommandActivityLeaseDocument
                { activityOwnerProcessGroup = ownerProcessGroup,
                  activityCommandIdentity = anchorIdentity,
                  activityIdentities =
                    CommandActivityDurable
                      ownerIdentity
                      supervisorIdentity
                      pinIdentity
                }
        if all validActivityProcessId (ownerProcessGroup : processIds)
          then validateCommandActivityTopology activity >> Right activity
          else Left "bounded-command incoming intent process identities are invalid"

    splitOnDot value =
      case break (== '.') value of
        (component, []) -> [component]
        (component, _ : remainder) -> component : splitOnDot remainder

    parsePositiveHex ::
      (Integral value) =>
      String ->
      String ->
      Either String value
    parsePositiveHex label value =
      case readHex value of
        [(parsed, "")]
          | parsed > 0 -> Right parsed
        _ -> Left ("bounded-command incoming intent has an invalid " <> label)

    takeFixedField width label value =
      let (field, remainder) = splitAt width value
       in if length field == width
            then Right (field, remainder)
            else
              Left
                ( "bounded-command distinct-token incoming intent has a truncated "
                    <> label
                )

    parseIncomingBirthIdentity bootIdentity startTime =
      maybe
        (Left "bounded-command incoming intent has an invalid birth identity")
        Right
        ( parseProcessBirthIdentity
            (bootIdentity <> ":" <> show (startTime :: Word64))
        )

    unlessEither predicate failure
      | predicate = Right ()
      | otherwise = Left failure

commandActivityLeaseFileName :: CommandActivityLeaseDocument -> FilePath
commandActivityLeaseFileName activity =
  "activity-"
    <> ByteString8.unpack
      (Base16.encode (SHA256.hashlazy (Aeson.encode activity)))
    <> ".lease.json"

commandActivityLeaseMode :: FileMode
commandActivityLeaseMode = ownerReadMode .|. ownerWriteMode

maximumActivityDocumentBytes :: Int
maximumActivityDocumentBytes = 65536

maximumActivityLeaseEntries :: Integer
maximumActivityLeaseEntries = 4096

withBoundedActivityRoot ::
  FilePath ->
  (Fd -> IO a) ->
  IO a
withBoundedActivityRoot activityRoot action = mask $ \restore -> do
  listedStatus <- getSymbolicLinkStatus activityRoot
  unless
    ( isDirectory listedStatus
        && not (isSymbolicLink listedStatus)
        && fileMode listedStatus .&. 0o777 == ownerModes
    )
    ( ioError
        ( userError
            ( "bounded-command activity root is not one real 0700 directory: "
                <> activityRoot
            )
        )
    )
  descriptor <-
    openFd
      activityRoot
      ReadOnly
      defaultFileFlags
        { nofollow = True,
          directory = True,
          cloexec = True
        }
  finallyPreservingPrimary
    ( restore $ do
        openedStatus <- getFdStatus descriptor
        unless
          (exactMutationDirectoryStatus listedStatus openedStatus)
          (ioError (userError "bounded-command activity root changed while opening"))
        result <- action descriptor
        finalStatus <- getSymbolicLinkStatus activityRoot
        unless
          ( exactMutationDirectoryStatus openedStatus finalStatus
              && not (isSymbolicLink finalStatus)
          )
          ( ioError
              (userError "bounded-command activity root changed during recovery")
          )
        pure result
    )
    (ignoreIOException (closeFd descriptor))

synchroniseDirectory :: FilePath -> IO ()
synchroniseDirectory directoryPath = mask $ \restore -> do
  descriptor <- openFd directoryPath ReadOnly defaultFileFlags
  finallyPreservingPrimary
    (restore (fileSynchronise descriptor))
    (ignoreIOException (closeFd descriptor))

plannedCommandActivity ::
  FilePath ->
  FilePath ->
  CommandActivityLeaseDocument ->
  PublishedCommandActivity
plannedCommandActivity activeRuntimeRoot incomingName activity =
  PublishedCommandActivity
    { publishedActivityDocument = activity,
      publishedActivityPath =
        commandActivityRoot activeRuntimeRoot
          </> commandActivityLeaseFileName activity,
      publishedActivityIncomingPath =
        commandActivityRoot activeRuntimeRoot </> incomingName
    }

data ActivityProcessGroupStatus
  = ActivityProcessGroupAbsent
  | ActivityProcessGroupActive
  | ActivityProcessGroupUnverifiable !String

inspectActivityProcessGroup ::
  String ->
  ActivityProcessIdentity ->
  IO ActivityProcessGroupStatus
inspectActivityProcessGroup label identity = do
  let processGroup = activityProcessGroup identity
      processId = activityProcessId identity
  observedIdentityBefore <- readProcessBirthIdentity processId
  groupProbe <-
    try
      (signalProcessGroup nullSignal (fromIntegral processGroup)) ::
      IO (Either IOException ())
  observedIdentityAfter <- readProcessBirthIdentity processId
  case groupProbe of
    Left failure
      | isDoesNotExistError failure ->
          pure
            ( classifyAbsentActivityProcessGroup
                label
                identity
                observedIdentityBefore
                observedIdentityAfter
            )
      | isPermissionError failure ->
          -- Darwin can report EPERM while a just-exited group still has
          -- unreaped kernel state. It is not absence evidence; keep polling
          -- until ESRCH or the bounded proof deadline.
          pure ActivityProcessGroupActive
      | otherwise ->
          pure
            ( ActivityProcessGroupUnverifiable
                ( "cannot inspect bounded-command "
                    <> label
                    <> " process group "
                    <> show processGroup
                    <> ": "
                    <> displayException failure
                )
            )
    Right () -> do
      pure
        ( classifyObservedActivityProcessGroup
            label
            identity
            observedIdentityAfter
        )

classifyAbsentActivityProcessGroup ::
  String ->
  ActivityProcessIdentity ->
  Maybe ProcessBirthIdentity ->
  Maybe ProcessBirthIdentity ->
  ActivityProcessGroupStatus
classifyAbsentActivityProcessGroup
  label
  expectedIdentity
  observedIdentityBefore
  observedIdentityAfter
    | any isMismatched [observedIdentityBefore, observedIdentityAfter] =
        refuse "leader PID was reused across the kernel absence observation"
    | observedIdentityAfter
        == Just (activityProcessBirthIdentity expectedIdentity) =
        refuse "exact leader remains live outside its recorded process group"
    | otherwise =
        ActivityProcessGroupAbsent
    where
      isMismatched observedIdentity =
        case observedIdentity of
          Nothing -> False
          Just observed ->
            observed /= activityProcessBirthIdentity expectedIdentity
      refuse reason =
        ActivityProcessGroupUnverifiable
          ( "cannot prove bounded-command "
              <> label
              <> " process group "
              <> show (activityProcessGroup expectedIdentity)
              <> " absent: "
              <> reason
          )

classifyObservedActivityProcessGroup ::
  String ->
  ActivityProcessIdentity ->
  Maybe ProcessBirthIdentity ->
  ActivityProcessGroupStatus
classifyObservedActivityProcessGroup label expectedIdentity observedIdentity =
  case observedIdentity of
    Just identity
      | identity == activityProcessBirthIdentity expectedIdentity ->
          ActivityProcessGroupActive
      | otherwise ->
          ActivityProcessGroupUnverifiable
            ( "live bounded-command "
                <> label
                <> " process group "
                <> show (activityProcessGroup expectedIdentity)
                <> " has a mismatched leader birth identity"
            )
    -- The direct process can exit while descendants still retain its original
    -- process group. A live PGID cannot be reused until that group disappears.
    Nothing -> ActivityProcessGroupActive

awaitRecordedProcessGroupAbsent ::
  String ->
  ActivityProcessIdentity ->
  Int ->
  IO ()
awaitRecordedProcessGroupAbsent label identity attemptsRemaining = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.budgetDeadline attemptsRemaining 10000)
      probe
  Readiness.foldReadiness
    pure
    (const (ioError timeoutFailure))
    (const (ioError timeoutFailure))
    outcome
  where
    probe = do
      status <- inspectActivityProcessGroup label identity
      case status of
        ActivityProcessGroupAbsent -> pure (Right ())
        ActivityProcessGroupActive ->
          pure
            ( Left
                Readiness.Progress
                  { Readiness.progressObserved = 0,
                    Readiness.progressExpected = 1,
                    Readiness.progressDetail =
                      Text.pack
                        ( "still live: "
                            <> label
                            <> ":"
                            <> show (activityProcessGroup identity)
                        )
                  }
            )
        ActivityProcessGroupUnverifiable refusal ->
          ioError (userError refusal)
    timeoutFailure =
      userError
        ( "bounded-command "
            <> label
            <> " process group did not exit after cancellation: "
            <> show (activityProcessGroup identity)
        )

awaitProvisionalProcessQuiescent ::
  String ->
  ProvisionalProcessIdentity ->
  IO ()
awaitProvisionalProcessQuiescent label identity = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.pollLimitedDeadline 10000 2 2 501)
      probe
  Readiness.foldReadiness
    pure
    (const (ioError timeoutFailure))
    (const (ioError timeoutFailure))
    outcome
  where
    processId = provisionalProcessId identity
    probe = do
      observedBirthIdentity <-
        readProcessBirthIdentity processId
      case observedBirthIdentity of
        Just observedIdentity
          | observedIdentity /= provisionalBirthIdentity identity ->
              ioError
                (userError ("bounded-command " <> label <> " pid was reused"))
          | otherwise ->
              pure
                ( Left
                    (Readiness.Progress 0 1 (Text.pack ("still live: " <> label)))
                )
        Nothing -> do
          groupProbe <-
            try @IOException
              (signalProcessGroup nullSignal (fromIntegral processId))
          case groupProbe of
            Left failure
              | isDoesNotExistError failure -> pure (Right ())
              | isPermissionError failure ->
                  pure
                    ( Left
                        ( Readiness.Progress
                            0
                            1
                            (Text.pack ("still present: " <> label))
                        )
                    )
              | otherwise -> ioError failure
            Right () ->
              pure
                ( Left
                    ( Readiness.Progress
                        0
                        1
                        (Text.pack ("detached group still live: " <> label))
                    )
                )
    timeoutFailure =
      userError
        ( "bounded-command provisional process did not become quiescent: "
            <> label
        )

activityProcessGroups ::
  CommandActivityLeaseDocument ->
  [(String, ActivityProcessIdentity)]
activityProcessGroups activity =
  [("command", activityCommandIdentity activity)]
    <> maybe
      []
      (pure . ("supervisor",))
      (activitySupervisorIdentity activity)
    <> maybe
      []
      (pure . ("target",))
      (activityTargetGroupLeaderIdentity activity)

readCommandActivityLease ::
  FilePath ->
  IO CommandActivityLeaseDocument
readCommandActivityLease activityPath = do
  activity <- readCommandActivityDocument activityPath
  if takeFileName activityPath == commandActivityLeaseFileName activity
    then pure activity
    else
      ioError
        ( userError
            ( "bounded-command activity lease digest does not match its contents: "
                <> activityPath
            )
        )

readCommandActivityDocument ::
  FilePath ->
  IO CommandActivityLeaseDocument
readCommandActivityDocument activityPath = mask $ \restore -> do
  descriptor <-
    restore
      ( openFd
          activityPath
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              cloexec = True
            }
      )
  finallyPreservingPrimary
    (restore (readValidatedActivityDocument descriptor))
    (ignoreIOException (closeFd descriptor))
  where
    readValidatedActivityDocument descriptor = do
      status <- getFdStatus descriptor
      let permissionBits = fileMode status .&. 0o777
      unless
        ( isRegularFile status
            && permissionBits == commandActivityLeaseMode
        )
        ( ioError
            ( userError
                ( "bounded-command activity lease is not a regular 0600 file: "
                    <> activityPath
                )
            )
        )
      contents <-
        readRegularFdPrefix
          (maximumActivityDocumentBytes + 1)
          descriptor
      when
        (ByteString.length contents > maximumActivityDocumentBytes)
        ( ioError
            ( userError
                ( "bounded-command activity lease exceeds its size limit: "
                    <> activityPath
                )
            )
        )
      either
        ( \decodeFailure ->
            ioError
              ( userError
                  ( "cannot decode bounded-command activity lease "
                      <> activityPath
                      <> ": "
                      <> decodeFailure
                  )
              )
        )
        pure
        (Aeson.eitherDecodeStrict' contents)

-- | Prove that no command process group published by the specified owner
-- process group remains live. A malformed lease, a live group, or a reused
-- live PID fails closed. Only an @ESRCH@ group probe permits lease removal.
proveBoundedCommandActivitiesQuiescent ::
  Paths ->
  Integer ->
  IO BoundedCommandActivitiesQuiescent
proveBoundedCommandActivitiesQuiescent paths ownerProcessGroup
  | not (validActivityProcessId ownerProcessGroup) =
      ioError
        ( userError
            ( "invalid bounded-command activity owner process group: "
                <> show ownerProcessGroup
            )
        )
  | otherwise = do
      let activityRoot = commandActivityRoot (runtimeRoot paths)
      rootStatus <-
        try (getSymbolicLinkStatus activityRoot) ::
          IO (Either IOException FileStatus)
      case rootStatus of
        Left failure
          | isDoesNotExistError failure ->
              pure (BoundedCommandActivitiesQuiescent ownerProcessGroup)
          | otherwise -> ioError failure
        Right status
          | not (isDirectory status)
              || fileMode status .&. 0o777 /= ownerModes ->
              ioError
                ( userError
                    ( "bounded-command activity root is not a 0700 directory: "
                        <> activityRoot
                    )
                )
          | otherwise -> do
              withBoundedActivityRoot activityRoot $ \descriptor -> do
                entries <-
                  listDirectoryBoundedFromDescriptor
                    descriptor
                    maximumActivityLeaseEntries
                mapM_
                  (proveEntryQuiescent activityRoot)
                  entries
              pure (BoundedCommandActivitiesQuiescent ownerProcessGroup)
  where
    proveEntryQuiescent activityRoot entry
      | ".incoming-activity-" `List.isPrefixOf` entry = do
          let incomingPath = activityRoot </> entry
          activity <-
            either
              (ioError . userError)
              pure
              (commandActivityFromIncomingFileName entry)
          when
            (activityOwnerProcessGroup activity == ownerProcessGroup)
            (reconcileIncomingActivity incomingPath activity)
      | ".lease.json" `List.isSuffixOf` entry = do
          let activityPath = activityRoot </> entry
          activity <- readCommandActivityLease activityPath
          when
            (activityOwnerProcessGroup activity == ownerProcessGroup)
            (proveActivityQuiescent activityPath activity)
      | otherwise =
          ioError
            ( userError
                ( "unexpected entry in bounded-command activity root: "
                    <> (activityRoot </> entry)
                )
            )

    reconcileIncomingActivity incomingPath activity = do
      -- The fsynced incoming filename is the prewrite intent and carries every
      -- exact identity needed for recovery, so even an empty or truncated
      -- payload can be retired without PID-only inference.
      requireActivityOwnerDead activity
      proveActivityQuiescent incomingPath activity

-- | Recover every bounded-command activity whose exact owner has died, while
-- preserving records owned by unrelated exact-live commands. The activity
-- filename carries the complete prepublication identity, so truncated incoming
-- records remain recoverable without PID-only inference.
recoverAbandonedBoundedCommandActivities ::
  Paths ->
  IO AbandonedActivitiesRecovered
recoverAbandonedBoundedCommandActivities paths = do
  let activeRuntimeRoot = runtimeRoot paths
      activityRoot = commandActivityRoot activeRuntimeRoot
  rootStatus <-
    try (getSymbolicLinkStatus activityRoot) ::
      IO (Either IOException FileStatus)
  case rootStatus of
    Left failure
      | isDoesNotExistError failure ->
          pure (AbandonedActivitiesRecovered activeRuntimeRoot)
      | otherwise -> ioError failure
    Right status
      | not (isDirectory status)
          || fileMode status .&. 0o777 /= ownerModes ->
          ioError
            ( userError
                ( "bounded-command activity root is not a 0700 directory: "
                    <> activityRoot
                )
            )
      | otherwise -> do
          withBoundedActivityRoot activityRoot $ \descriptor -> do
            entries <-
              listDirectoryBoundedFromDescriptor
                descriptor
                maximumActivityLeaseEntries
            mapM_ (recoverEntry activityRoot) entries
          pure (AbandonedActivitiesRecovered activeRuntimeRoot)
  where
    recoverEntry activityRoot entry
      | ".incoming-activity-" `List.isPrefixOf` entry = do
          let activityPath = activityRoot </> entry
          activity <-
            either
              (ioError . userError)
              pure
              (commandActivityFromIncomingFileName entry)
          recoverIfOwnerAbandoned activityPath activity
      | ".lease.json" `List.isSuffixOf` entry = do
          let activityPath = activityRoot </> entry
          activity <- readCommandActivityLease activityPath
          recoverIfOwnerAbandoned activityPath activity
      | otherwise =
          ioError
            ( userError
                ( "unexpected entry in bounded-command activity root: "
                    <> (activityRoot </> entry)
                )
            )

    recoverIfOwnerAbandoned activityPath activity = do
      exactOwnerLive <- activityExactOwnerIsLive activity
      unless exactOwnerLive (proveActivityQuiescent activityPath activity)

proveActivityQuiescent ::
  FilePath ->
  CommandActivityLeaseDocument ->
  IO ()
proveActivityQuiescent activityPath activity = do
  observations <-
    mapM
      observeRecoverableProcessGroup
      (activityProcessGroups activity)
  case [ ()
       | (_, _, RecoverableProcessGroupActive) <- observations
       ] of
    [] -> pure ()
    _ : _ -> do
      requireActivityOwnerDead activity
      let recoveryGroups = activityRecoveryProcessGroups activity
      finallyPreservingPrimary
        ( runCleanupsPreservingFailures
            [ deferSignalFailureUntilAbsence
                (signalActivityProcessGroupWith sigCONT identity)
            | (_, identity) <- recoveryGroups
            ]
        )
        ( runCleanupsPreservingFailures
            [ finallyPreservingPrimary
                ( deferSignalFailureUntilAbsence
                    (signalActivityProcessGroup identity)
                )
                (awaitRecordedProcessGroupAbsent label identity 500)
            | (label, identity) <- recoveryGroups
            ]
        )
      mapM_
        ( \(label, identity) ->
            awaitRecordedProcessGroupAbsent label identity 500
        )
        (activityProcessGroups activity)
  removeFile activityPath
  synchroniseDirectory (takeDirectory activityPath)

data RecoverableProcessGroupStatus
  = RecoverableProcessGroupAbsent
  | RecoverableProcessGroupActive

observeRecoverableProcessGroup ::
  (String, ActivityProcessIdentity) ->
  IO (String, ActivityProcessIdentity, RecoverableProcessGroupStatus)
observeRecoverableProcessGroup (label, identity) = do
  groupProbe <-
    try @IOException
      ( signalProcessGroup
          nullSignal
          (fromIntegral (activityProcessGroup identity))
      )
  case groupProbe of
    Left failure
      | isDoesNotExistError failure ->
          pure (label, identity, RecoverableProcessGroupAbsent)
      | isPermissionError failure ->
          -- EPERM is not absence. Recovery must still run and the later
          -- bounded group proof must reach ESRCH before retirement.
          pure (label, identity, RecoverableProcessGroupActive)
      | otherwise -> ioError failure
    Right () -> do
      observedBirthIdentityBefore <-
        readProcessBirthIdentity (activityProcessId identity)
      case observedBirthIdentityBefore of
        Just observedIdentity
          | observedIdentity == activityProcessBirthIdentity identity -> do
              observedProcessGroupResult <-
                try @IOException
                  ( getProcessGroupIDOf
                      (fromIntegral (activityProcessId identity))
                  )
              case observedProcessGroupResult of
                Left failure
                  | isDoesNotExistError failure -> do
                      observedBirthIdentityAfter <-
                        readProcessBirthIdentity (activityProcessId identity)
                      case observedBirthIdentityAfter of
                        Just laterIdentity
                          | laterIdentity
                              /= activityProcessBirthIdentity identity ->
                              refuse "leader identity changed during observation"
                        _ ->
                          pure
                            (label, identity, RecoverableProcessGroupActive)
                  | otherwise -> ioError failure
                Right observedProcessGroup -> do
                  observedBirthIdentityAfter <-
                    readProcessBirthIdentity (activityProcessId identity)
                  case observedBirthIdentityAfter of
                    -- A leader that is simply gone is the sibling branch's
                    -- ordinary case, and the group reading above was taken
                    -- while the pre-read still proved the exact leader, so it
                    -- stays attributable evidence. Only a leader observed as a
                    -- different process is reuse.
                    Just laterIdentity
                      | laterIdentity
                          /= activityProcessBirthIdentity identity ->
                          refuse "leader identity changed during observation"
                    _ ->
                      if fromIntegral observedProcessGroup
                        /= activityProcessGroup identity
                        then refuse "leader moved outside its recorded group"
                        else
                          if activityProcessId identity
                            /= activityProcessGroup identity
                            then refuse "recorded identity is not the process-group leader"
                            else
                              pure
                                ( label,
                                  identity,
                                  RecoverableProcessGroupActive
                                )
        Just _ ->
          refuse "leader birth identity does not match"
        -- The direct process can exit while descendants still retain its
        -- original process group, and a live PGID cannot be reused until that
        -- group disappears. An absent leader over a live group is therefore
        -- the ordinary abandoned-activity shape, not a reuse. 'Active' is also
        -- the conservative verdict here: it is the one that makes the caller
        -- run the full owner-death check, signal sweep, and bounded
        -- group-absence proof rather than retiring the lease.
        Nothing ->
          pure (label, identity, RecoverableProcessGroupActive)
  where
    refuse reason =
      ioError
        ( userError
            ( "cannot recover bounded-command "
                <> label
                <> " process group "
                <> show (activityProcessGroup identity)
                <> ": "
                <> reason
            )
        )

requireActivityOwnerDead ::
  CommandActivityLeaseDocument ->
  IO ()
requireActivityOwnerDead activity =
  case activityOwnerIdentity activity of
    Nothing ->
      ioError
        ( userError
            "refusing bounded-command activity recovery because this legacy lease has no exact owner birth identity"
        )
    Just ownerIdentity -> do
      let ownerProcessId =
            activityProcessId ownerIdentity
          ownerBirthIdentity =
            activityProcessBirthIdentity ownerIdentity
      observedBirthIdentity <-
        readProcessBirthIdentity ownerProcessId
      case observedBirthIdentity of
        Just observedIdentity
          | observedIdentity == ownerBirthIdentity ->
              refuseExactOwnerLive ownerIdentity
          | otherwise ->
              pure ()
        Nothing -> do
          ownerProbe <-
            try @IOException
              (signalProcess nullSignal (fromIntegral ownerProcessId))
          case ownerProbe of
            Left failure
              | isDoesNotExistError failure -> pure ()
              -- EPERM is liveness, not absence: the pid is allocated to a
              -- process this uid may not signal. It must classify as the
              -- unverifiable-owner refusal rather than escape as a bare errno,
              -- and it must never be read as owner death — on Darwin the birth
              -- identity is registry-backed, so an unregistered live process
              -- reads as 'Nothing' here and only this probe distinguishes it.
              | isPermissionError failure -> refuseUnverifiableOwner
              | otherwise -> ioError failure
            Right () -> refuseUnverifiableOwner
          where
            refuseUnverifiableOwner =
              ioError
                ( userError
                    ( "refusing bounded-command activity recovery because the live owner birth identity is unverifiable: "
                        <> show ownerProcessId
                    )
                )

activityExactOwnerIsLive ::
  CommandActivityLeaseDocument ->
  IO Bool
activityExactOwnerIsLive activity =
  case activityOwnerIdentity activity of
    Nothing ->
      ioError
        ( userError
            "refusing bounded-command abandoned-activity recovery because this legacy lease has no exact owner birth identity"
        )
    Just ownerIdentity -> do
      let ownerProcessId = activityProcessId ownerIdentity
          ownerBirthIdentity =
            activityProcessBirthIdentity ownerIdentity
      observedBirthIdentity <-
        readProcessBirthIdentity ownerProcessId
      case observedBirthIdentity of
        Just observedIdentity ->
          pure (observedIdentity == ownerBirthIdentity)
        Nothing -> do
          ownerProbe <-
            try @IOException
              (signalProcess nullSignal (fromIntegral ownerProcessId))
          case ownerProbe of
            Left failure
              | isDoesNotExistError failure -> pure False
              -- EPERM is liveness, not absence. Returning 'False' here would
              -- declare a live-but-unsignalable owner dead and let an
              -- abandoned-activity sweep reclaim its lease, so it refuses.
              | isPermissionError failure -> refuseUnverifiableOwner
              | otherwise -> ioError failure
            Right () -> refuseUnverifiableOwner
          where
            refuseUnverifiableOwner =
              ioError
                ( userError
                    ( "refusing bounded-command abandoned-activity recovery because the live owner birth identity is unverifiable: "
                        <> show ownerProcessId
                    )
                )

refuseExactOwnerLive :: ActivityProcessIdentity -> IO ()
refuseExactOwnerLive ownerIdentity =
  ioError
    ( userError
        ( "refusing bounded-command activity recovery while the exact owner process remains live: "
            <> show (activityProcessId ownerIdentity)
        )
    )

activityRecoveryProcessGroups ::
  CommandActivityLeaseDocument ->
  [(String, ActivityProcessIdentity)]
activityRecoveryProcessGroups activity =
  maybe
    []
    (\identity -> [("target", identity)])
    (activityTargetGroupLeaderIdentity activity)
    <> maybe
      []
      (\identity -> [("supervisor", identity)])
      (activitySupervisorIdentity activity)
    <> [("anchor", activityCommandIdentity activity)]

awaitActivityProcessGroupAbsent ::
  CommandActivityLeaseDocument ->
  Int ->
  IO ()
awaitActivityProcessGroupAbsent activity attemptsRemaining = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.budgetDeadline attemptsRemaining 10000)
      probe
  Readiness.foldReadiness
    pure
    (const (ioError timeoutFailure))
    (const (ioError timeoutFailure))
    outcome
  where
    probe = do
      statuses <-
        mapM
          ( \(label, identity) -> do
              status <- inspectActivityProcessGroup label identity
              pure (label, identity, status)
          )
          (activityProcessGroups activity)
      case [ refusal
           | (_, _, ActivityProcessGroupUnverifiable refusal) <- statuses
           ] of
        refusal : _ -> ioError (userError refusal)
        [] ->
          case [ label <> ":" <> show (activityProcessGroup identity)
               | (label, identity, ActivityProcessGroupActive) <- statuses
               ] of
            [] -> pure (Right ())
            activeGroups ->
              pure
                ( Left
                    ( Readiness.Progress
                        0
                        1
                        (Text.pack ("still live: " <> List.intercalate ", " activeGroups))
                    )
                )
    timeoutFailure =
      userError
        ( "bounded-command process groups did not exit after cancellation: "
            <> List.intercalate
              ", "
              [ label <> ":" <> show (activityProcessGroup identity)
              | (label, identity) <- activityProcessGroups activity
              ]
        )

retirePublishedCommandActivity :: PublishedCommandActivity -> IO ()
retirePublishedCommandActivity publishedActivity = do
  awaitActivityProcessGroupAbsent
    (publishedActivityDocument publishedActivity)
    500
  runCleanupsPreservingFailures
    [ retireActivityPath (publishedActivityPath publishedActivity),
      retireActivityPath (publishedActivityIncomingPath publishedActivity)
    ]
  where
    retireActivityPath activityPath = do
      removal <-
        try (removeFile activityPath) ::
          IO (Either IOException ())
      case removal of
        Right () -> synchroniseDirectory (takeDirectory activityPath)
        Left failure
          | isDoesNotExistError failure -> pure ()
          | otherwise -> ioError failure

runActivityRetirementTestHook :: CommandIdentity -> IO ()
runActivityRetirementTestHook identity =
  case activityRetirementTestPaths identity of
    Nothing -> pure ()
    Just (readyPath, releaseFifo) -> do
      startedAt <- getMonotonicTimeNSec
      release <-
        runActionBeforeDeadline
          (deadlineAfterMicros startedAt 5000000)
          (readNamedPipePayloadAfterReady readyPath releaseFifo)
      unless (release == "release\n") $
        ioError
          (userError "bounded-command activity retirement release was invalid")

classifyExit :: ExitCode -> String -> String -> CommandOutcome
classifyExit ExitSuccess out _ = CommandSucceeded out
classifyExit (ExitFailure code) out err =
  CommandFailedFatal
    ("exit " <> show code <> "\nstdout:\n" <> out <> "\nstderr:\n" <> err)

pollTrackedProcess :: TrackedProcess -> IO (Maybe ProcessStatus)
pollTrackedProcess tracked = do
  (maybeStatus, newlyReaped) <-
    modifyMVar (trackedProcessStatus tracked) $ \cachedStatus ->
      case cachedStatus of
        Just processStatus -> pure (cachedStatus, (Just processStatus, False))
        Nothing -> do
          maybeStatus <-
            getProcessStatus False False (trackedProcessId tracked)
          pure (maybeStatus, (maybeStatus, isJust maybeStatus))
  when newlyReaped (releaseTrackedProcessRegistration tracked)
  pure maybeStatus

releaseTrackedProcessRegistration :: TrackedProcess -> IO ()
releaseTrackedProcessRegistration tracked =
  modifyMVar_
    (trackedProcessRegistration tracked)
    ( \maybeRegistration -> do
        mapM_
          ProcessIdentityInternal.releaseRegisteredProcessIdentity
          maybeRegistration
        pure Nothing
    )

waitForTrackedProcessBounded :: TrackedProcess -> IO ProcessStatus
waitForTrackedProcessBounded tracked = do
  status <- waitForTrackedProcessMaybe tracked
  maybe
    ( ioError
        ( userError
            ( "runBoundedCommand: timed out reaping owned child pid "
                <> show (trackedProcessId tracked)
            )
        )
    )
    pure
    status

ignoreIOException :: IO () -> IO ()
ignoreIOException action = do
  _ <- try @IOException action
  pure ()

exceptionFailures :: Either SomeException a -> [SomeException]
exceptionFailures =
  either pure (const [])

isAsynchronousException :: SomeException -> Bool
isAsynchronousException failure =
  case fromException failure :: Maybe SomeAsyncException of
    Just _ -> True
    Nothing -> False

requireBoundedProcessReap :: String -> ProcessID -> IO ()
requireBoundedProcessReap label processId = do
  reapResult <- timeout 1000000 (getProcessStatus True False processId)
  case reapResult of
    Just (Just _) -> pure ()
    Just Nothing ->
      ioError
        ( userError
            ( "runBoundedCommand: "
                <> label
                <> " pid "
                <> show processId
                <> " produced no reap status"
            )
        )
    Nothing ->
      ioError
        ( userError
            ( "runBoundedCommand: timed out reaping "
                <> label
                <> " pid "
                <> show processId
            )
        )

-- The bounded-command helper kernel uses only public Haskell process APIs.
-- The parent creates one clean self-exec anchor. The anchor creates and reaps
-- the supervisor through another clean standard-stream boundary; only the
-- supervisor owns the private pipes used by its forked target and group pin.

internalAnchorMode :: String
internalAnchorMode = "__infernix_internal_command_anchor_v2"

internalSupervisorMode :: String
internalSupervisorMode = "__infernix_internal_command_supervisor_v2"

internalPinMode :: String
internalPinMode = "__infernix_internal_command_pin_v3"

internalProvisioningMutationMode :: String
internalProvisioningMutationMode =
  "__infernix_internal_provisioning_mutation_v1"

internalSynchronousTreeTargetMode :: String
internalSynchronousTreeTargetMode =
  "__infernix_internal_synchronous_tree_target_v1"

-- | The only argument shape a self-exec sentinel target may carry: the
-- synchronous-tree mode selector followed by exactly the declared identity
-- path.
selfExecTreeTargetArguments :: Maybe FilePath -> [String] -> Bool
selfExecTreeTargetArguments synchronousExceptionIdentityPath arguments =
  case (synchronousExceptionIdentityPath, arguments) of
    (Just expectedPath, [mode, identityPath]) ->
      mode == internalSynchronousTreeTargetMode
        && expectedPath == identityPath
    _ -> False

-- | A retained executable expectation is admissible only for a relative
-- generation-custodied target that names the configured executable, carries no
-- test hook, and declares valid package/runtime closure aggregates.
validRetainedExecutableExpectation ::
  Maybe FilePath ->
  FilePath ->
  Maybe ExecutableSnapshotExpectation ->
  Bool
validRetainedExecutableExpectation
  relativeExecutable
  executable
  retainedExecutableExpectation =
    case retainedExecutableExpectation of
      Nothing -> True
      Just expectation ->
        isJust relativeExecutable
          && normalise (snapshotConfiguredPath expectation)
            == normalise executable
          && isNothing (snapshotTestHook expectation)
          && validPackageClosureSnapshotAggregate
            (snapshotPackageClosures expectation)
          && validRuntimeLibrarySnapshotAggregate
            (snapshotRuntimeLibraries expectation)

internalSynchronousDescendantMode :: String
internalSynchronousDescendantMode =
  "__infernix_internal_synchronous_descendant_v1"

internalSelfExecutableSentinel :: FilePath
internalSelfExecutableSentinel =
  "/__infernix_internal_self_executable__"

maximumSupervisorFrameBytes :: Int
maximumSupervisorFrameBytes = 67108864

maximumCapturedOutputBytes :: Int
maximumCapturedOutputBytes = 16777216

maximumEncodedCapturedOutputBytes :: Int
maximumEncodedCapturedOutputBytes =
  4 * ((maximumCapturedOutputBytes + 2) `div` 3)

maximumHelperDiagnosticBytes :: Int
maximumHelperDiagnosticBytes = 1048576

maximumTargetSetupFrameBytes :: Int
maximumTargetSetupFrameBytes = 4096

maximumExecutableSnapshotBytes :: Integer
maximumExecutableSnapshotBytes = 128 * 1024 * 1024

maximumPackageClosureSnapshotBytes :: Integer
maximumPackageClosureSnapshotBytes = 512 * 1024 * 1024

maximumPackageClosureSnapshotFiles :: Integer
maximumPackageClosureSnapshotFiles = 100000

maximumPackageClosureSnapshotDepth :: Int
maximumPackageClosureSnapshotDepth = 64

maximumPackageClosureSnapshots :: Int
maximumPackageClosureSnapshots = 16

maximumRuntimeLibrarySnapshots :: Int
maximumRuntimeLibrarySnapshots = 512

maximumRuntimeLibrarySnapshotFileBytes :: Integer
maximumRuntimeLibrarySnapshotFileBytes = 128 * 1024 * 1024

maximumRuntimeLibrarySnapshotBytes :: Integer
maximumRuntimeLibrarySnapshotBytes = 256 * 1024 * 1024

validPackageClosureSnapshotAggregate ::
  [PackageClosureSnapshotExpectation] ->
  Bool
validPackageClosureSnapshotAggregate closures =
  length closures <= maximumPackageClosureSnapshots
    && sum (map closureSnapshotBytes closures)
      <= maximumPackageClosureSnapshotBytes
    && sum (map closureSnapshotFiles closures)
      <= maximumPackageClosureSnapshotFiles
    && length (List.nub (map (normalise . closureSnapshotRoot) closures))
      == length closures

validRuntimeLibrarySnapshotAggregate ::
  [RuntimeLibrarySnapshotExpectation] ->
  Bool
validRuntimeLibrarySnapshotAggregate libraries =
  length libraries <= maximumRuntimeLibrarySnapshots
    && sum (map runtimeLibrarySnapshotSize libraries)
      <= maximumRuntimeLibrarySnapshotBytes
    && all
      (safeRuntimeLibraryLeaf . runtimeLibrarySnapshotLeafName)
      libraries
    && length
      (List.nub (map runtimeLibrarySnapshotLeafName libraries))
      == length libraries
    && length
      ( List.nub
          ( map
              (normalise . runtimeLibrarySnapshotCanonicalPath)
              libraries
          )
      )
      == length libraries

safeRuntimeLibraryLeaf :: FilePath -> Bool
safeRuntimeLibraryLeaf leafName =
  not (null leafName)
    && leafName == takeFileName leafName
    && leafName /= "."
    && leafName /= ".."
    && '\NUL' `notElem` leafName

maximumProtocolExitCode :: Int
maximumProtocolExitCode = 255

maximumProtocolSignalNumber :: Int
maximumProtocolSignalNumber = 127

data ArtifactLeaseExpectation = ArtifactLeaseExpectation
  { artifactLeaseAdapterId :: !Text.Text,
    artifactLeaseSubstrate :: !Text.Text,
    artifactLeaseArchitecture :: !Text.Text,
    artifactLeaseInstallRoot :: !FilePath,
    artifactLeaseManifestFingerprint :: !Text.Text
  }
  deriving (Eq, Show)

-- | The engines root, adapter, generation fingerprint, and payload digest a
-- helper is handed, plus the lane the parent resolved the target from.
--
-- The lane is carried because without it a helper structurally cannot re-derive
-- the closed catalog entry it is being asked to validate, and would have to
-- assume one. Assuming @apple-silicon@ is precisely what made the
-- @linux-native@ smoke unable to pass on any input.
data ArtifactGenerationLeaseExpectation
  = ArtifactGenerationLeaseExpectation
      !FilePath
      !Text.Text
      !Text.Text
      !Text.Text
      !Text.Text
      !Text.Text
  deriving (Eq, Show)

artifactGenerationLeaseExpectation ::
  Text.Text ->
  Text.Text ->
  ArtifactGenerationLease ->
  ArtifactGenerationLeaseExpectation
artifactGenerationLeaseExpectation substrate architecture lease =
  case artifactGenerationLeaseFields lease of
    (enginesRoot, adapterId, generationFingerprint, payloadDigest) ->
      ArtifactGenerationLeaseExpectation
        enginesRoot
        adapterId
        generationFingerprint
        payloadDigest
        substrate
        architecture

artifactGenerationLeaseExpectationLane ::
  ArtifactGenerationLeaseExpectation ->
  (Text.Text, Text.Text)
artifactGenerationLeaseExpectationLane
  ( ArtifactGenerationLeaseExpectation
      _
      _
      _
      _
      substrate
      architecture
    ) = (substrate, architecture)

-- | The roots a sealed run may legitimately load from.
--
-- An installed artifact owns its generation root; an image target owns the
-- closure roots its catalog entry declares, because the payload it execs lives
-- in the immutable image rather than in the generation. Both come from the same
-- closed catalog entry, resolved from the lane the expectation names, so the
-- audit cannot admit a root the target contract never declared.
sealedRunOwnedRoots ::
  ArtifactGenerationLeaseExpectation ->
  ProvisioningMutationRoot ->
  Either String [FilePath]
sealedRunOwnedRoots expectation retainedRoot =
  case expectation of
    ArtifactGenerationLeaseExpectation
      _
      adapterId
      _
      _
      substrate
      architecture -> do
        identity <-
          maybe
            (Left "sealed run expectation has no closed adapter identity")
            Right
            (ArtifactIdentity.parseNativeArtifactIdentity adapterId)
        target <-
          ArtifactTarget.nativeArtifactTarget identity substrate architecture
        pure
          ( ArtifactTarget.nativeArtifactTargetImmutableClosureRoots
              (provisioningMutationRootPath retainedRoot)
              target
          )

-- | The exact root a retained provisioning mutation authority owns.
--
-- This is the root the command may actually execute and mutate within, which
-- during a pre-activation smoke is the candidate sibling rather than the final
-- install root the generation lease names.
provisioningMutationWireRootPath ::
  ProvisioningMutationWorkingDirectoryWire ->
  FilePath
provisioningMutationWireRootPath
  (ProvisioningMutationWorkingDirectoryWire root _ _) =
    mutationWireRootPath root

artifactGenerationLeaseFromExpectation ::
  ArtifactGenerationLeaseExpectation ->
  Either String ArtifactGenerationLease
artifactGenerationLeaseFromExpectation
  ( ArtifactGenerationLeaseExpectation
      enginesRoot
      adapterId
      generationFingerprint
      payloadDigest
      _substrate
      _architecture
    ) = do
    identity <-
      maybe
        (Left "artifact generation lease has no closed adapter identity")
        Right
        (ArtifactIdentity.parseNativeArtifactIdentity adapterId)
    artifactGenerationLease
      enginesRoot
      identity
      generationFingerprint
      payloadDigest

data SupervisorPlan = SupervisorPlan
  { supervisorPlanAnchorIdentity :: !ActivityProcessIdentity,
    supervisorPlanHelperEnvironment :: ![(String, String)],
    supervisorPlanExecutable :: !FilePath,
    supervisorPlanExecutableSnapshot ::
      !(Maybe ExecutableSnapshotExpectation),
    supervisorPlanRetainedExecutableExpectation ::
      !(Maybe ExecutableSnapshotExpectation),
    supervisorPlanExecutableSnapshotRoot :: !FilePath,
    supervisorPlanArguments :: ![String],
    supervisorPlanInput :: !ByteString.ByteString,
    supervisorPlanEnvironment :: ![(String, String)],
    supervisorPlanWorkingDirectory :: !(Maybe FilePath),
    supervisorPlanProvisioningMutationWorkingDirectory ::
      !(Maybe ProvisioningMutationWorkingDirectoryWire),
    supervisorPlanArtifactLeaseExpectation ::
      !(Maybe ArtifactLeaseExpectation),
    supervisorPlanArtifactGenerationLeaseExpectation ::
      !(Maybe ArtifactGenerationLeaseExpectation),
    supervisorPlanInstalledPythonSourceIsolationExpectation ::
      !(Maybe InstalledPythonSourceIsolationExpectation),
    supervisorPlanForceControlFailure :: !Bool,
    supervisorPlanForceTargetSetupFailure :: !Bool,
    supervisorPlanAnchorPrePublicationDeathPath :: !(Maybe FilePath),
    supervisorPlanPrePreparedStopPath :: !(Maybe FilePath),
    supervisorPlanCustodyHandoffStopPath :: !(Maybe FilePath),
    supervisorPlanSynchronousExceptionIdentityPath :: !(Maybe FilePath),
    supervisorPlanProtocolIsolationReadyPath :: !(Maybe FilePath),
    supervisorPlanReapEvidencePrefix :: !(Maybe FilePath),
    supervisorPlanTerminalObservationPath :: !(Maybe FilePath),
    supervisorPlanProtocolEvidenceCase :: !(Maybe TestProtocolEvidenceCase)
  }
  deriving (Eq, Show)

data TargetTerminal
  = TargetExited !Int
  | TargetSignaled !Int !Bool
  | TargetKernelFailure !String
  deriving (Eq, Show)

data SynchronousExceptionTreeEvidence = SynchronousExceptionTreeEvidence
  { synchronousTargetIdentity :: !ActivityProcessIdentity,
    synchronousDescendantIdentity :: !ActivityProcessIdentity,
    synchronousGroupLeaderIdentity :: !ActivityProcessIdentity
  }
  deriving (Eq, Show)

data InputEvidence
  = InputCompleted
  | InputFailed !String
  deriving (Eq, Show)

data CaptureEvidence
  = CaptureCompleted !ByteString.ByteString
  | CaptureFailed !String
  deriving (Eq, Show)

data SupervisorRequest
  = SupervisorConfigure !SupervisorPlan
  | SupervisorDetach
  | SupervisorAcknowledgePin
  | SupervisorOpenTargetGate
  deriving (Eq, Show)

data SupervisorEvent
  = SupervisorDetached !ActivityProcessIdentity
  | SupervisorPinBorn !ProvisionalProcessIdentity
  | SupervisorPrepared !ActivityProcessIdentity
  | SupervisorTerminal
      !TargetTerminal
      !InputEvidence
      !CaptureEvidence
      !CaptureEvidence
  deriving (Eq, Show)

data PinRequest
  = PinDetach
  | PinRetain
  deriving (Eq, Show)

data PinEvent
  = PinTargetGroupReady !ActivityProcessIdentity
  | PinRetained
  deriving (Eq, Show)

newtype HelperIdentityReady
  = HelperIdentityReady ActivityProcessIdentity
  deriving (Eq, Show)

data TargetSetupEvent
  = TargetBorn !Integer !Integer
  | TargetIdentityReady !ActivityProcessIdentity
  | TargetSetupFailed !String
  deriving (Eq, Show)

data AnchorEvent
  = AnchorSupervisorBorn !ProvisionalProcessIdentity
  | AnchorPinBorn !ProvisionalProcessIdentity
  | AnchorSupervisorReady
      !ActivityProcessIdentity
      !ActivityProcessIdentity
  | AnchorTerminal
      !ExitCode
      !TargetTerminal
      !InputEvidence
      !CaptureEvidence
      !CaptureEvidence
  | AnchorKernelFailure !String
  deriving (Eq, Show)

data AnchorWake
  = AnchorSupervisorEvent !(Either IOException SupervisorEvent)
  | AnchorParentRequest !(Either IOException ())

data AnchorPreparationWake
  = AnchorPreparationSupervisor !(Either IOException SupervisorEvent)
  | AnchorPreparationParentClosed !(Either IOException ())

data SupervisorWake
  = SupervisorTargetTerminal
  | SupervisorPinTerminal
  | SupervisorParentClosed
  | SupervisorControlFailed !String

instance Aeson.ToJSON HelperIdentityReady where
  toJSON (HelperIdentityReady identity) =
    Aeson.object
      ( [ "version" Aeson..= (1 :: Int),
          "event" Aeson..= ("helper-identity-ready" :: String)
        ]
          <> identityJsonFields "helper" identity
      )

instance Aeson.FromJSON HelperIdentityReady where
  parseJSON =
    Aeson.withObject "HelperIdentityReady" $ \value -> do
      version <- value Aeson..: "version"
      eventName <- value Aeson..: "event"
      unless
        ( version == (1 :: Int)
            && eventName == ("helper-identity-ready" :: String)
        )
        (fail "invalid bounded-command helper-identity event")
      HelperIdentityReady
        <$> parsePrefixedMemberIdentity value "helper"

instance Aeson.ToJSON TargetSetupEvent where
  toJSON event =
    case event of
      TargetBorn processId processGroup ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "event" Aeson..= ("target-born" :: String),
            "processId" Aeson..= processId,
            "processGroup" Aeson..= processGroup
          ]
      TargetIdentityReady identity ->
        Aeson.object
          ( [ "version" Aeson..= (2 :: Int),
              "event" Aeson..= ("target-identity-ready" :: String)
            ]
              <> identityJsonFields "target" identity
          )
      TargetSetupFailed failure ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "event" Aeson..= ("target-setup-failed" :: String),
            "failure" Aeson..= failure
          ]

instance Aeson.FromJSON TargetSetupEvent where
  parseJSON =
    Aeson.withObject "TargetSetupEvent" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (2 :: Int)) $
        fail "unsupported bounded-command target-setup event version"
      eventName <- value Aeson..: "event"
      case eventName :: String of
        "target-born" -> do
          processId <- value Aeson..: "processId"
          processGroup <- value Aeson..: "processGroup"
          unless
            ( validActivityProcessId processId
                && validActivityProcessId processGroup
            )
            (fail "invalid bounded-command target-setup identity")
          pure (TargetBorn processId processGroup)
        "target-identity-ready" ->
          TargetIdentityReady
            <$> parsePrefixedMemberIdentity value "target"
        "target-setup-failed" ->
          TargetSetupFailed <$> value Aeson..: "failure"
        _ -> fail "unknown bounded-command target-setup event"

instance Aeson.ToJSON TestProtocolEvidenceCase where
  toJSON evidenceCase =
    Aeson.String $
      case evidenceCase of
        ProtocolCaptureAtLimit -> "capture-at-limit"
        ProtocolCaptureOverLimit -> "capture-over-limit"
        ProtocolTargetExitAtLimit -> "target-exit-at-limit"
        ProtocolTargetExitNegative -> "target-exit-negative"
        ProtocolTargetExitOverLimit -> "target-exit-over-limit"
        ProtocolTargetSignalAtLimit -> "target-signal-at-limit"
        ProtocolTargetSignalZero -> "target-signal-zero"
        ProtocolTargetSignalNegative -> "target-signal-negative"
        ProtocolTargetSignalOverLimit -> "target-signal-over-limit"
        ProtocolSupervisorExitAtLimit -> "supervisor-exit-at-limit"
        ProtocolSupervisorExitNegative -> "supervisor-exit-negative"
        ProtocolSupervisorExitOverLimit -> "supervisor-exit-over-limit"

instance Aeson.FromJSON TestProtocolEvidenceCase where
  parseJSON =
    Aeson.withText "TestProtocolEvidenceCase" $ \case
      "capture-at-limit" -> pure ProtocolCaptureAtLimit
      "capture-over-limit" -> pure ProtocolCaptureOverLimit
      "target-exit-at-limit" -> pure ProtocolTargetExitAtLimit
      "target-exit-negative" -> pure ProtocolTargetExitNegative
      "target-exit-over-limit" -> pure ProtocolTargetExitOverLimit
      "target-signal-at-limit" -> pure ProtocolTargetSignalAtLimit
      "target-signal-zero" -> pure ProtocolTargetSignalZero
      "target-signal-negative" -> pure ProtocolTargetSignalNegative
      "target-signal-over-limit" -> pure ProtocolTargetSignalOverLimit
      "supervisor-exit-at-limit" -> pure ProtocolSupervisorExitAtLimit
      "supervisor-exit-negative" -> pure ProtocolSupervisorExitNegative
      "supervisor-exit-over-limit" -> pure ProtocolSupervisorExitOverLimit
      _ -> fail "unknown bounded-command protocol-evidence test case"

instance Aeson.ToJSON ExecutableSnapshotExpectation where
  toJSON expectation =
    Aeson.object
      [ "configuredPath" Aeson..= snapshotConfiguredPath expectation,
        "canonicalPath" Aeson..= snapshotCanonicalPath expectation,
        "deviceId" Aeson..= snapshotDeviceId expectation,
        "fileId" Aeson..= snapshotFileId expectation,
        "mode" Aeson..= snapshotMode expectation,
        "size" Aeson..= snapshotSize expectation,
        "digest" Aeson..= snapshotDigest expectation,
        "packageClosures" Aeson..= snapshotPackageClosures expectation,
        "runtimeLibraries" Aeson..= snapshotRuntimeLibraries expectation,
        "testHook" Aeson..= snapshotTestHook expectation
      ]

instance Aeson.FromJSON ExecutableSnapshotExpectation where
  parseJSON =
    Aeson.withObject "ExecutableSnapshotExpectation" $ \value -> do
      expectation <-
        ExecutableSnapshotExpectation
          <$> value Aeson..: "configuredPath"
          <*> value Aeson..: "canonicalPath"
          <*> value Aeson..: "deviceId"
          <*> value Aeson..: "fileId"
          <*> value Aeson..: "mode"
          <*> value Aeson..: "size"
          <*> value Aeson..: "digest"
          <*> value Aeson..: "packageClosures"
          <*> value Aeson..: "runtimeLibraries"
          <*> value Aeson..: "testHook"
      unless
        ( isAbsolute (snapshotConfiguredPath expectation)
            && isAbsolute (snapshotCanonicalPath expectation)
            && snapshotDeviceId expectation >= 0
            && snapshotFileId expectation > 0
            && snapshotMode expectation > 0
            && snapshotSize expectation >= 0
            && snapshotSize expectation <= maximumExecutableSnapshotBytes
            && "sha256:" `Text.isPrefixOf` snapshotDigest expectation
            && Text.length (snapshotDigest expectation) == 71
            && validPackageClosureSnapshotAggregate
              (snapshotPackageClosures expectation)
            && validRuntimeLibrarySnapshotAggregate
              (snapshotRuntimeLibraries expectation)
        )
        (fail "bounded-command executable snapshot expectation is invalid")
      pure expectation

instance Aeson.ToJSON ExactExecutableSnapshotTestPoint where
  toJSON testPoint =
    Aeson.String $
      case testPoint of
        MutateBeforeAnchorSnapshot -> "before-anchor-snapshot"
        MutateAfterAnchorSnapshot -> "after-anchor-snapshot"

instance Aeson.FromJSON ExactExecutableSnapshotTestPoint where
  parseJSON =
    Aeson.withText "ExactExecutableSnapshotTestPoint" $ \case
      "before-anchor-snapshot" -> pure MutateBeforeAnchorSnapshot
      "after-anchor-snapshot" -> pure MutateAfterAnchorSnapshot
      _ -> fail "unknown exact executable snapshot test point"

instance Aeson.ToJSON ExecutableSnapshotTestHook where
  toJSON hook =
    Aeson.object
      [ "point" Aeson..= snapshotTestPoint hook,
        "readyPath" Aeson..= snapshotTestReadyPath hook,
        "releasePath" Aeson..= snapshotTestReleasePath hook
      ]

instance Aeson.FromJSON ExecutableSnapshotTestHook where
  parseJSON =
    Aeson.withObject "ExecutableSnapshotTestHook" $ \value -> do
      hook <-
        ExecutableSnapshotTestHook
          <$> value Aeson..: "point"
          <*> value Aeson..: "readyPath"
          <*> value Aeson..: "releasePath"
      unless
        ( isAbsolute (snapshotTestReadyPath hook)
            && isAbsolute (snapshotTestReleasePath hook)
        )
        (fail "exact executable snapshot test hook paths are not absolute")
      pure hook

instance Aeson.ToJSON PackageClosureSnapshotRole where
  toJSON role =
    Aeson.String $
      case role of
        SnapshotPythonHome -> "python-home"
        SnapshotPythonPath -> "python-path"
        SnapshotProjectSource -> "project-source"
        SnapshotArtifactRoot -> "artifact-root"

instance Aeson.FromJSON PackageClosureSnapshotRole where
  parseJSON =
    Aeson.withText "PackageClosureSnapshotRole" $ \case
      "python-home" -> pure SnapshotPythonHome
      "python-path" -> pure SnapshotPythonPath
      "project-source" -> pure SnapshotProjectSource
      "artifact-root" -> pure SnapshotArtifactRoot
      _ -> fail "unknown bounded-command package closure snapshot role"

instance Aeson.ToJSON PackageClosureSnapshotExpectation where
  toJSON expectation =
    Aeson.object
      [ "role" Aeson..= closureSnapshotRole expectation,
        "root" Aeson..= closureSnapshotRoot expectation,
        "deviceId" Aeson..= closureSnapshotDeviceId expectation,
        "fileId" Aeson..= closureSnapshotFileId expectation,
        "mode" Aeson..= closureSnapshotMode expectation,
        "bytes" Aeson..= closureSnapshotBytes expectation,
        "files" Aeson..= closureSnapshotFiles expectation,
        "digest" Aeson..= closureSnapshotDigest expectation
      ]

instance Aeson.FromJSON PackageClosureSnapshotExpectation where
  parseJSON =
    Aeson.withObject "PackageClosureSnapshotExpectation" $ \value -> do
      expectation <-
        PackageClosureSnapshotExpectation
          <$> value Aeson..: "role"
          <*> value Aeson..: "root"
          <*> value Aeson..: "deviceId"
          <*> value Aeson..: "fileId"
          <*> value Aeson..: "mode"
          <*> value Aeson..: "bytes"
          <*> value Aeson..: "files"
          <*> value Aeson..: "digest"
      unless
        ( isAbsolute (closureSnapshotRoot expectation)
            && closureSnapshotDeviceId expectation >= 0
            && closureSnapshotFileId expectation > 0
            && closureSnapshotMode expectation > 0
            && closureSnapshotBytes expectation >= 0
            && closureSnapshotBytes expectation <= maximumPackageClosureSnapshotBytes
            && closureSnapshotFiles expectation >= 0
            && closureSnapshotFiles expectation <= maximumPackageClosureSnapshotFiles
            && "sha256:" `Text.isPrefixOf` closureSnapshotDigest expectation
            && Text.length (closureSnapshotDigest expectation) == 71
        )
        (fail "bounded-command package closure snapshot expectation is invalid")
      pure expectation

instance Aeson.ToJSON RuntimeLibrarySnapshotExpectation where
  toJSON expectation =
    Aeson.object
      [ "leafName" Aeson..= runtimeLibrarySnapshotLeafName expectation,
        "configuredPath"
          Aeson..= runtimeLibrarySnapshotConfiguredPath expectation,
        "canonicalPath"
          Aeson..= runtimeLibrarySnapshotCanonicalPath expectation,
        "deviceId" Aeson..= runtimeLibrarySnapshotDeviceId expectation,
        "fileId" Aeson..= runtimeLibrarySnapshotFileId expectation,
        "mode" Aeson..= runtimeLibrarySnapshotMode expectation,
        "size" Aeson..= runtimeLibrarySnapshotSize expectation,
        "digest" Aeson..= runtimeLibrarySnapshotDigest expectation
      ]

instance Aeson.FromJSON RuntimeLibrarySnapshotExpectation where
  parseJSON =
    Aeson.withObject "RuntimeLibrarySnapshotExpectation" $ \value -> do
      expectation <-
        RuntimeLibrarySnapshotExpectation
          <$> value Aeson..: "leafName"
          <*> value Aeson..: "configuredPath"
          <*> value Aeson..: "canonicalPath"
          <*> value Aeson..: "deviceId"
          <*> value Aeson..: "fileId"
          <*> value Aeson..: "mode"
          <*> value Aeson..: "size"
          <*> value Aeson..: "digest"
      unless
        ( safeRuntimeLibraryLeaf
            (runtimeLibrarySnapshotLeafName expectation)
            && isAbsolute
              (runtimeLibrarySnapshotConfiguredPath expectation)
            && isAbsolute
              (runtimeLibrarySnapshotCanonicalPath expectation)
            && runtimeLibrarySnapshotDeviceId expectation >= 0
            && runtimeLibrarySnapshotFileId expectation > 0
            && runtimeLibrarySnapshotMode expectation > 0
            && runtimeLibrarySnapshotSize expectation >= 0
            && runtimeLibrarySnapshotSize expectation
              <= maximumRuntimeLibrarySnapshotFileBytes
            && "sha256:"
              `Text.isPrefixOf` runtimeLibrarySnapshotDigest expectation
            && Text.length (runtimeLibrarySnapshotDigest expectation) == 71
        )
        (fail "bounded-command runtime library snapshot expectation is invalid")
      pure expectation

instance Aeson.ToJSON ArtifactLeaseExpectation where
  toJSON expectation =
    Aeson.object
      [ "adapterId" Aeson..= artifactLeaseAdapterId expectation,
        "substrate" Aeson..= artifactLeaseSubstrate expectation,
        "architecture" Aeson..= artifactLeaseArchitecture expectation,
        "installRoot" Aeson..= artifactLeaseInstallRoot expectation,
        "manifestFingerprint"
          Aeson..= artifactLeaseManifestFingerprint expectation
      ]

instance Aeson.FromJSON ArtifactLeaseExpectation where
  parseJSON =
    Aeson.withObject "ArtifactLeaseExpectation" $ \value -> do
      expectation <-
        ArtifactLeaseExpectation
          <$> value Aeson..: "adapterId"
          <*> value Aeson..: "substrate"
          <*> value Aeson..: "architecture"
          <*> value Aeson..: "installRoot"
          <*> value Aeson..: "manifestFingerprint"
      unless
        ( not (Text.null (artifactLeaseAdapterId expectation))
            && not (Text.any (== '\0') (artifactLeaseAdapterId expectation))
            && artifactLeaseSubstrate expectation
              `elem` ["apple-silicon", "linux-native"]
            && not (Text.null (artifactLeaseArchitecture expectation))
            && not
              (Text.any (== '\0') (artifactLeaseArchitecture expectation))
            && isAbsolute (artifactLeaseInstallRoot expectation)
            && canonicalSha256Fingerprint
              (artifactLeaseManifestFingerprint expectation)
        )
        (fail "bounded-command artifact lease expectation is invalid")
      pure expectation
    where
      canonicalSha256Fingerprint fingerprint =
        case Text.stripPrefix "sha256:" fingerprint of
          Just suffix ->
            Text.length suffix == 64
              && Text.all (`Text.elem` "0123456789abcdef") suffix
          Nothing -> False

instance Aeson.ToJSON ArtifactGenerationLeaseExpectation where
  toJSON
    ( ArtifactGenerationLeaseExpectation
        enginesRoot
        adapterId
        generationFingerprint
        payloadDigest
        substrate
        architecture
      ) =
      Aeson.object
        [ "enginesRoot" Aeson..= enginesRoot,
          "adapterId" Aeson..= adapterId,
          "generationFingerprint" Aeson..= generationFingerprint,
          "payloadDigest" Aeson..= payloadDigest,
          "substrate" Aeson..= substrate,
          "architecture" Aeson..= architecture
        ]

instance Aeson.FromJSON ArtifactGenerationLeaseExpectation where
  parseJSON =
    Aeson.withObject "ArtifactGenerationLeaseExpectation" $ \value -> do
      expectation <-
        ArtifactGenerationLeaseExpectation
          <$> value Aeson..: "enginesRoot"
          <*> value Aeson..: "adapterId"
          <*> value Aeson..: "generationFingerprint"
          <*> value Aeson..: "payloadDigest"
          <*> value Aeson..: "substrate"
          <*> value Aeson..: "architecture"
      either
        fail
        (const (pure expectation))
        (artifactGenerationLeaseFromExpectation expectation)

instance Aeson.ToJSON InstalledPythonSourceIsolationExpectation where
  toJSON expectation =
    Aeson.object
      [ "adapterId"
          Aeson..= Provisioning.appleAdapterSlug
            (sourceIsolationExpectationAdapter expectation),
        "auditInjector"
          Aeson..= sourceIsolationExpectationAuditInjector expectation,
        "directories"
          Aeson..= sourceIsolationExpectationDirectories expectation,
        "files" Aeson..= sourceIsolationExpectationFiles expectation,
        "writableProbe"
          Aeson..= sourceIsolationExpectationWritableProbe expectation,
        "receiptDigest"
          Aeson..= sourceIsolationExpectationReceiptDigest expectation
      ]

instance Aeson.FromJSON InstalledPythonSourceIsolationExpectation where
  parseJSON =
    Aeson.withObject "InstalledPythonSourceIsolationExpectation" $ \value -> do
      adapterSlug <- value Aeson..: "adapterId"
      adapter <-
        case [ candidate
             | candidate <- [minBound .. maxBound],
               Provisioning.appleAdapterSlug candidate == adapterSlug,
               isJust (Provisioning.applePythonAdapterForApple candidate)
             ] of
          [candidate] -> pure candidate
          _ -> fail "source-isolation expectation names no unique Python adapter"
      expectation <-
        InstalledPythonSourceIsolationExpectation adapter
          <$> value Aeson..: "auditInjector"
          <*> value Aeson..: "directories"
          <*> value Aeson..: "files"
          <*> value Aeson..: "writableProbe"
          <*> value Aeson..: "receiptDigest"
      either fail pure (validateInstalledPythonSourceIsolationExpectation expectation)
      pure expectation

instance Aeson.ToJSON SupervisorPlan where
  toJSON plan =
    Aeson.object
      [ "version" Aeson..= (12 :: Int),
        "anchorProcessId"
          Aeson..= activityProcessId (supervisorPlanAnchorIdentity plan),
        "anchorProcessGroup"
          Aeson..= activityProcessGroup (supervisorPlanAnchorIdentity plan),
        "anchorBirthIdentity"
          Aeson..= renderProcessBirthIdentity
            (activityProcessBirthIdentity (supervisorPlanAnchorIdentity plan)),
        "helperEnvironment" Aeson..= supervisorPlanHelperEnvironment plan,
        "executable" Aeson..= supervisorPlanExecutable plan,
        "executableSnapshot"
          Aeson..= supervisorPlanExecutableSnapshot plan,
        "retainedExecutableExpectation"
          Aeson..= supervisorPlanRetainedExecutableExpectation plan,
        "executableSnapshotRoot"
          Aeson..= supervisorPlanExecutableSnapshotRoot plan,
        "arguments" Aeson..= supervisorPlanArguments plan,
        "inputBase64"
          Aeson..= TextEncoding.decodeUtf8
            (Base64.encode (supervisorPlanInput plan)),
        "environment" Aeson..= supervisorPlanEnvironment plan,
        "workingDirectory" Aeson..= supervisorPlanWorkingDirectory plan,
        "provisioningMutationWorkingDirectory"
          Aeson..= supervisorPlanProvisioningMutationWorkingDirectory plan,
        "artifactLeaseExpectation"
          Aeson..= supervisorPlanArtifactLeaseExpectation plan,
        "artifactGenerationLeaseExpectation"
          Aeson..= supervisorPlanArtifactGenerationLeaseExpectation plan,
        "installedPythonSourceIsolationExpectation"
          Aeson..= supervisorPlanInstalledPythonSourceIsolationExpectation plan,
        "forceControlFailure" Aeson..= supervisorPlanForceControlFailure plan,
        "forceTargetSetupFailure"
          Aeson..= supervisorPlanForceTargetSetupFailure plan,
        "anchorPrePublicationDeathPath"
          Aeson..= supervisorPlanAnchorPrePublicationDeathPath plan,
        "prePreparedStopPath"
          Aeson..= supervisorPlanPrePreparedStopPath plan,
        "custodyHandoffStopPath"
          Aeson..= supervisorPlanCustodyHandoffStopPath plan,
        "synchronousExceptionIdentityPath"
          Aeson..= supervisorPlanSynchronousExceptionIdentityPath plan,
        "protocolIsolationReadyPath"
          Aeson..= supervisorPlanProtocolIsolationReadyPath plan,
        "reapEvidencePrefix"
          Aeson..= supervisorPlanReapEvidencePrefix plan,
        "terminalObservationPath"
          Aeson..= supervisorPlanTerminalObservationPath plan,
        "protocolEvidenceTestCase"
          Aeson..= supervisorPlanProtocolEvidenceCase plan
      ]

instance Aeson.FromJSON SupervisorPlan where
  parseJSON =
    Aeson.withObject "SupervisorPlan" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (12 :: Int)) $
        fail "unsupported bounded-command supervisor-plan version"
      anchorIdentity <-
        parseActivityProcessIdentity
          value
          "anchorProcessId"
          "anchorProcessGroup"
          "anchorBirthIdentity"
      helperEnvironment <- value Aeson..: "helperEnvironment"
      executable <- value Aeson..: "executable"
      executableSnapshot <- value Aeson..: "executableSnapshot"
      retainedExecutableExpectation <-
        value Aeson..: "retainedExecutableExpectation"
      executableSnapshotRoot <- value Aeson..: "executableSnapshotRoot"
      arguments <- value Aeson..: "arguments"
      inputBase64 <- value Aeson..: "inputBase64"
      input <-
        either
          (fail . ("invalid bounded-command input base64: " <>))
          pure
          (Base64.decode (TextEncoding.encodeUtf8 inputBase64))
      environment <- value Aeson..: "environment"
      workingDirectory <- value Aeson..: "workingDirectory"
      provisioningMutationWorkingDirectory <-
        value Aeson..: "provisioningMutationWorkingDirectory"
      artifactLeaseExpectation <-
        value Aeson..: "artifactLeaseExpectation"
      artifactGenerationLeaseExpectationValue <-
        value Aeson..: "artifactGenerationLeaseExpectation"
      installedPythonSourceIsolationExpectationValue <-
        value Aeson..: "installedPythonSourceIsolationExpectation"
      forceControlFailure <- value Aeson..: "forceControlFailure"
      forceTargetSetupFailure <- value Aeson..: "forceTargetSetupFailure"
      anchorPrePublicationDeathPath <-
        value Aeson..: "anchorPrePublicationDeathPath"
      prePreparedStopPath <- value Aeson..: "prePreparedStopPath"
      custodyHandoffStopPath <- value Aeson..: "custodyHandoffStopPath"
      synchronousExceptionIdentityPath <-
        value Aeson..: "synchronousExceptionIdentityPath"
      protocolIsolationReadyPath <-
        value Aeson..: "protocolIsolationReadyPath"
      reapEvidencePrefix <- value Aeson..: "reapEvidencePrefix"
      terminalObservationPath <- value Aeson..: "terminalObservationPath"
      protocolEvidenceCase <- value Aeson..: "protocolEvidenceTestCase"
      unless (isAbsolute executable) $
        fail "bounded-command supervisor target executable is not absolute"
      unless (isAbsolute executableSnapshotRoot) $
        fail "bounded-command executable snapshot root is not absolute"
      unless
        ( executable /= internalSelfExecutableSentinel
            || selfExecTreeTargetArguments
              synchronousExceptionIdentityPath
              arguments
              && isNothing executableSnapshot
              && isNothing retainedExecutableExpectation
              && isNothing provisioningMutationWorkingDirectory
              && isNothing artifactLeaseExpectation
              && isNothing artifactGenerationLeaseExpectationValue
              && isNothing installedPythonSourceIsolationExpectationValue
        )
        (fail "bounded-command internal self-exec authority has an invalid shape")
      unless (maybe True isAbsolute terminalObservationPath) $
        fail "bounded-command supervisor observation path is not absolute"
      unless (maybe True isAbsolute anchorPrePublicationDeathPath) $
        fail "bounded-command anchor pre-publication death path is not absolute"
      unless (maybe True isAbsolute prePreparedStopPath) $
        fail "bounded-command supervisor pre-prepared path is not absolute"
      unless (maybe True isAbsolute custodyHandoffStopPath) $
        fail "bounded-command supervisor custody-handoff path is not absolute"
      unless (maybe True isAbsolute synchronousExceptionIdentityPath) $
        fail "bounded-command supervisor synchronous-exception path is not absolute"
      unless (maybe True isAbsolute protocolIsolationReadyPath) $
        fail "bounded-command supervisor protocol-isolation path is not absolute"
      unless (maybe True isAbsolute reapEvidencePrefix) $
        fail "bounded-command supervisor reap-evidence prefix is not absolute"
      unless (maybe True isAbsolute workingDirectory) $
        fail "bounded-command supervisor working directory is not absolute"
      unless
        ( isNothing workingDirectory
            || isNothing provisioningMutationWorkingDirectory
        )
        (fail "bounded-command has two working-directory authorities")
      unless
        (isNothing executableSnapshot || isNothing retainedExecutableExpectation)
        (fail "bounded-command has two executable authorities")
      let relativeExecutable =
            provisioningMutationWorkingDirectory
              >>= ( \( ProvisioningMutationWorkingDirectoryWire
                         _
                         _
                         wireExecutable
                       ) -> wireExecutable
                  )
          retainedExecutablePath =
            provisioningMutationWorkingDirectory
              >>= ( \( ProvisioningMutationWorkingDirectoryWire
                         wireRoot
                         components
                         maybeExecutable
                       ) ->
                        ( \relativePath ->
                            foldl
                              (</>)
                              (mutationWireRootPath wireRoot)
                              components
                              </> relativePath
                        )
                          <$> maybeExecutable
                  )
      unless
        ( maybe
            True
            ((== normalise executable) . normalise)
            retainedExecutablePath
        )
        (fail "bounded-command retained target path disagrees with its executable")
      unless
        ( isNothing relativeExecutable
            || ( isNothing executableSnapshot
                   && ( isJust artifactGenerationLeaseExpectationValue
                          || isJust retainedExecutableExpectation
                      )
               )
        )
        ( fail
            "bounded-command relative target lacks generation custody or attempts executable snapshotting"
        )
      unless
        ( validRetainedExecutableExpectation
            relativeExecutable
            executable
            retainedExecutableExpectation
        )
        (fail "bounded-command retained executable expectation is invalid")
      either
        fail
        pure
        ( validateSupervisorInstalledPythonSourceIsolationShape
            executable
            executableSnapshot
            retainedExecutableExpectation
            arguments
            workingDirectory
            provisioningMutationWorkingDirectory
            artifactLeaseExpectation
            artifactGenerationLeaseExpectationValue
            installedPythonSourceIsolationExpectationValue
        )
      either fail pure (validateSupervisorHelperEnvironment helperEnvironment)
      either
        fail
        pure
        ( validateSupervisorTargetEnvironment
            executableSnapshotRoot
            ( map
                normalise
                ( maybe [] (pure . artifactLeaseInstallRoot) artifactLeaseExpectation
                    <> maybe
                      []
                      (pure . provisioningMutationWireRootPath)
                      provisioningMutationWorkingDirectory
                )
            )
            helperEnvironment
            environment
        )
      pure
        SupervisorPlan
          { supervisorPlanAnchorIdentity = anchorIdentity,
            supervisorPlanHelperEnvironment = helperEnvironment,
            supervisorPlanExecutable = executable,
            supervisorPlanExecutableSnapshot = executableSnapshot,
            supervisorPlanRetainedExecutableExpectation =
              retainedExecutableExpectation,
            supervisorPlanExecutableSnapshotRoot = executableSnapshotRoot,
            supervisorPlanArguments = arguments,
            supervisorPlanInput = input,
            supervisorPlanEnvironment = environment,
            supervisorPlanWorkingDirectory = workingDirectory,
            supervisorPlanProvisioningMutationWorkingDirectory =
              provisioningMutationWorkingDirectory,
            supervisorPlanArtifactLeaseExpectation =
              artifactLeaseExpectation,
            supervisorPlanArtifactGenerationLeaseExpectation =
              artifactGenerationLeaseExpectationValue,
            supervisorPlanInstalledPythonSourceIsolationExpectation =
              installedPythonSourceIsolationExpectationValue,
            supervisorPlanForceControlFailure = forceControlFailure,
            supervisorPlanForceTargetSetupFailure =
              forceTargetSetupFailure,
            supervisorPlanAnchorPrePublicationDeathPath =
              anchorPrePublicationDeathPath,
            supervisorPlanPrePreparedStopPath = prePreparedStopPath,
            supervisorPlanCustodyHandoffStopPath = custodyHandoffStopPath,
            supervisorPlanSynchronousExceptionIdentityPath =
              synchronousExceptionIdentityPath,
            supervisorPlanProtocolIsolationReadyPath =
              protocolIsolationReadyPath,
            supervisorPlanReapEvidencePrefix = reapEvidencePrefix,
            supervisorPlanTerminalObservationPath = terminalObservationPath,
            supervisorPlanProtocolEvidenceCase = protocolEvidenceCase
          }

validExplicitEnvironment :: [(String, String)] -> Bool
validExplicitEnvironment environment =
  uniqueEnvironmentNames environment
    && all
      ( \(name, value) ->
          not (null name)
            && '=' `notElem` name
            && '\NUL' `notElem` name
            && '\NUL' `notElem` value
      )
      environment

validateSupervisorHelperEnvironment ::
  [(String, String)] ->
  Either String ()
validateSupervisorHelperEnvironment environment = do
  validateSupervisorEnvironmentSyntax "helper" environment
  unless
    (List.sort (map fst environment) == List.sort supervisorBaseEnvironmentNames)
    (Left "bounded-command helper environment does not match the closed base environment")
  validateSupervisorBaseEnvironment environment

validateSupervisorInstalledPythonSourceIsolationShape ::
  FilePath ->
  Maybe ExecutableSnapshotExpectation ->
  Maybe ExecutableSnapshotExpectation ->
  [String] ->
  Maybe FilePath ->
  Maybe ProvisioningMutationWorkingDirectoryWire ->
  Maybe ArtifactLeaseExpectation ->
  Maybe ArtifactGenerationLeaseExpectation ->
  Maybe InstalledPythonSourceIsolationExpectation ->
  Either String ()
validateSupervisorInstalledPythonSourceIsolationShape
  executable
  executableSnapshot
  retainedExecutableExpectation
  arguments
  workingDirectory
  mutationWorkingDirectory
  artifactLeaseExpectation
  generationLeaseExpectation
  maybeExpectation =
    case maybeExpectation of
      Nothing -> Right ()
      Just expectation -> do
        validateInstalledPythonSourceIsolationExpectation expectation
        artifactRoot <-
          case mutationWorkingDirectory of
            Just
              ( ProvisioningMutationWorkingDirectoryWire
                  wireRoot
                  []
                  Nothing
                ) ->
                Right (mutationWireRootPath wireRoot)
            _ ->
              Left
                "source-isolation wrapper lacks its exact retained artifact root"
        let adapter = sourceIsolationExpectationAdapter expectation
            sourcePaths = sourceIsolationExpectationSourcePaths expectation
            expectedArguments =
              Provisioning.installedPythonSourceIsolationArgumentsForPaths
                adapter
                artifactRoot
                (sourceIsolationExpectationDirectoryPaths expectation)
                (sourceIsolationExpectationFilePaths expectation)
                ( runtimeLibrarySnapshotCanonicalPath
                    (sourceIsolationExpectationWritableProbe expectation)
                )
                (sourceIsolationExpectationReceiptDigest expectation)
        unless
          ( normalise executable
              == normalise Provisioning.installedPythonSourceIsolationSandboxExecutable
              && isNothing workingDirectory
              && isNothing retainedExecutableExpectation
              && isNothing artifactLeaseExpectation
              && arguments == expectedArguments
              && all
                ( \sourcePath ->
                    not
                      ( pathWithinOwnedRoot sourcePath artifactRoot
                          || pathWithinOwnedRoot artifactRoot sourcePath
                      )
                )
                sourcePaths
          )
          (Left "source-isolation wrapper disagrees with its closed command shape")
        case executableSnapshot of
          Just sandboxSnapshot ->
            unless
              ( normalise (snapshotConfiguredPath sandboxSnapshot)
                  == normalise Provisioning.installedPythonSourceIsolationSandboxExecutable
                  && systemPlatformBinaryPath
                    (snapshotCanonicalPath sandboxSnapshot)
                  && null (snapshotPackageClosures sandboxSnapshot)
                  && null (snapshotRuntimeLibraries sandboxSnapshot)
                  && isNothing (snapshotTestHook sandboxSnapshot)
              )
              (Left "source-isolation wrapper lacks the exact sandbox platform identity")
          Nothing ->
            Left "source-isolation wrapper lacks the exact sandbox platform identity"
        case generationLeaseExpectation of
          Just
            ( ArtifactGenerationLeaseExpectation
                _enginesRoot
                adapterId
                _generationFingerprint
                _payloadDigest
                substrate
                architecture
              ) ->
              unless
                ( adapterId == Text.pack (Provisioning.appleAdapterSlug adapter)
                    && substrate == "apple-silicon"
                    && architecture == "arm64"
                )
                (Left "source-isolation wrapper generation lease disagrees with its adapter")
          Nothing ->
            Left "source-isolation wrapper lacks generation custody"

-- | Every extra-environment shape a production renderer can contribute to a
-- supervised target. The supervisor derives its admissible name sets from
-- these values; it does not restate the names produced by the command,
-- provisioning, package-snapshot, or installed-artifact renderers.
supervisorRenderedEnvironmentVocabulary :: [[(String, String)]]
supervisorRenderedEnvironmentVocabulary =
  List.nub
    ( Command.renderedCommandEnvironmentVocabulary
        <> [fixedProvisioningRenderedEnvironment []]
        <> pythonSnapshotRenderedEnvironmentVocabulary
        <> sealedArtifactRenderedEnvironmentVocabulary
    )

pythonSnapshotRenderedEnvironmentVocabulary :: [[(String, String)]]
pythonSnapshotRenderedEnvironmentVocabulary =
  [ renderPythonPackageClosureSnapshotEnvironment
      platform
      representativeSnapshotRoot
      (representativeSnapshotRoot </> "python-home")
      [representativeSnapshotRoot </> "python-path"]
      [representativeSnapshotRoot </> "project-source"]
      hasRuntimeLibraries
      <> fixedProvisioningRenderedEnvironment []
  | platform <- [PythonClosureLinux, PythonClosureNonLinux],
    hasRuntimeLibraries <- [False, True]
  ]
  where
    representativeSnapshotRoot =
      "/infernix-renderer-vocabulary/executable-snapshot"

sealedArtifactRenderedEnvironmentVocabulary :: [[(String, String)]]
sealedArtifactRenderedEnvironmentVocabulary =
  List.nub
    ( linuxSealedRunRenderedEnvironment
        : [ fixedProvisioningRenderedEnvironment
              ( artifactSnapshotRuntimeEnvironment
                  representativeArtifactRoot
                  (Provisioning.installedSmokeExecutableRelativePath adapter)
              )
          | adapter <- [minBound .. maxBound]
          ]
          <> [ fixedProvisioningRenderedEnvironment
                 ( installedPythonSourceIsolationRuntimeEnvironment
                     representativeArtifactRoot
                     (Provisioning.installedSmokeExecutableRelativePath adapter)
                 )
             | adapter <- [minBound .. maxBound],
               isJust (Provisioning.applePythonAdapterForApple adapter)
             ]
    )
  where
    representativeArtifactRoot =
      "/infernix-renderer-vocabulary/artifact"

supervisorTargetEnvironmentNameSets :: [[String]]
supervisorTargetEnvironmentNameSets =
  List.nub
    [ List.sort
        (map fst renderedEnvironment <> supervisorBaseEnvironmentNames)
    | renderedEnvironment <- supervisorRenderedEnvironmentVocabulary
    ]

-- | Validate the closed environment a supervised target may carry.
--
-- Runtime closure paths must stay inside a root this command already owns.
-- A snapshotting command owns its executable snapshot root. A command that
-- executes a sealed installed artifact under its generation lease owns that
-- artifact's install root instead, and its runtime closure legitimately
-- resolves there rather than in any snapshot.
validateSupervisorTargetEnvironment ::
  FilePath ->
  [FilePath] ->
  [(String, String)] ->
  [(String, String)] ->
  Either String ()
validateSupervisorTargetEnvironment
  executableSnapshotRoot
  artifactInstallRoots
  helperEnvironment
  targetEnvironment = do
    validateSupervisorEnvironmentSyntax "target" targetEnvironment
    let targetNames = List.sort (map fst targetEnvironment)
    unless
      (targetNames `elem` supervisorTargetEnvironmentNameSets)
      ( Left
          ( "bounded-command target environment does not match a closed rendered environment; names="
              <> show targetNames
          )
      )
    mapM_ requireMatchingBaseValue supervisorBaseEnvironmentNames
    case lookup "KUBECONFIG" targetEnvironment of
      Nothing -> pure ()
      Just kubeconfigPath
        | null kubeconfigPath ->
            Left "bounded-command target KUBECONFIG must be non-empty"
        | not (isAbsolute kubeconfigPath) ->
            Left "bounded-command target KUBECONFIG must be absolute"
        | otherwise -> pure ()
    case lookup "KUBERC" targetEnvironment of
      Nothing -> pure ()
      Just "off" -> pure ()
      Just _ -> Left "bounded-command target KUBERC must be off"
    case lookup "PYTHONDONTWRITEBYTECODE" targetEnvironment of
      Nothing -> pure ()
      Just "1" -> pure ()
      Just _ ->
        Left "bounded-command target PYTHONDONTWRITEBYTECODE must be 1"
    case lookup "PYTHONNOUSERSITE" targetEnvironment of
      Nothing -> pure ()
      Just "1" -> pure ()
      Just _ ->
        Left "bounded-command target PYTHONNOUSERSITE must be 1"
    case lookup "DYLD_PRINT_LIBRARIES" targetEnvironment of
      Nothing -> pure ()
      Just "1" -> pure ()
      Just _ ->
        Left "bounded-command target DYLD_PRINT_LIBRARIES must be 1"
    -- @libs@ is the exact glibc setting the ELF audit parses. A wider setting
    -- (@all@) would bury the load records in unrelated frames; a narrower one
    -- would emit none, and the audit would fail closed on its own evidence.
    case lookup "LD_DEBUG" targetEnvironment of
      Nothing -> pure ()
      Just "libs" -> pure ()
      Just _ ->
        Left "bounded-command target LD_DEBUG must be libs"
    mapM_
      validateAbsoluteEnvironmentPath
      [ value
      | name <-
          [ "PYTHONHOME",
            "GGML_BACKEND_PATH"
          ],
        value <- maybe [] pure (lookup name targetEnvironment)
      ]
    mapM_
      (mapM_ validateAbsoluteEnvironmentPath . splitSearchPath)
      [ value
      | name <-
          [ "DYLD_FRAMEWORK_PATH",
            "DYLD_LIBRARY_PATH"
          ],
        value <- maybe [] pure (lookup name targetEnvironment)
      ]
    case lookup "PYTHONPATH" targetEnvironment of
      Nothing -> pure ()
      Just pythonPath ->
        mapM_
          validateAbsoluteEnvironmentPath
          (splitSearchPath pythonPath)
    where
      requireMatchingBaseValue name =
        unless
          (lookup name targetEnvironment == lookup name helperEnvironment)
          (Left ("bounded-command target environment changed helper-owned " <> name))

      ownedClosureRoots =
        executableSnapshotRoot : artifactInstallRoots

      validateAbsoluteEnvironmentPath path
        | null path =
            Left "bounded-command Python closure path must be non-empty"
        | not (isAbsolute path) =
            Left "bounded-command Python closure path must be absolute"
        | not
            (any (`pathWithinOwnedRoot` path) ownedClosureRoots) =
            Left "bounded-command Python closure path escaped its owned roots"
        | otherwise = Right ()

validateSupervisorEnvironmentSyntax ::
  String ->
  [(String, String)] ->
  Either String ()
validateSupervisorEnvironmentSyntax label environment =
  unless
    (validExplicitEnvironment environment)
    (Left ("bounded-command " <> label <> " environment is invalid or has duplicate names"))

validateSupervisorBaseEnvironment ::
  [(String, String)] ->
  Either String ()
validateSupervisorBaseEnvironment environment = do
  searchPath <- requireSupervisorEnvironmentValue "PATH" environment
  unless
    (all (\component -> not (null component) && isAbsolute component) (splitSearchPath searchPath))
    (Left "bounded-command helper PATH must contain only absolute, non-empty components")
  mapM_
    requireAbsolutePath
    [ "HOME",
      "TMPDIR",
      "HELM_CONFIG_HOME",
      "HELM_CACHE_HOME",
      "HELM_DATA_HOME"
    ]
  language <- requireSupervisorEnvironmentValue "LANG" environment
  locale <- requireSupervisorEnvironmentValue "LC_ALL" environment
  unless
    (language == "C.UTF-8" && locale == language)
    (Left "bounded-command helper LANG and LC_ALL must both be C.UTF-8")
  where
    requireAbsolutePath name = do
      path <- requireSupervisorEnvironmentValue name environment
      unless
        (not (null path) && isAbsolute path)
        (Left ("bounded-command helper " <> name <> " must be absolute"))

requireSupervisorEnvironmentValue ::
  String ->
  [(String, String)] ->
  Either String String
requireSupervisorEnvironmentValue name environment =
  maybe
    (Left ("bounded-command environment is missing " <> name))
    Right
    (lookup name environment)

uniqueEnvironmentNames :: [(String, String)] -> Bool
uniqueEnvironmentNames environment =
  let names = map fst environment
   in length names == length (List.nub names)

supervisorBaseEnvironmentNames :: [String]
supervisorBaseEnvironmentNames =
  [ "PATH",
    "HOME",
    "TMPDIR",
    "LANG",
    "LC_ALL",
    "HELM_CONFIG_HOME",
    "HELM_CACHE_HOME",
    "HELM_DATA_HOME"
  ]

instance Aeson.ToJSON SupervisorRequest where
  toJSON request =
    case request of
      SupervisorConfigure plan ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("configure" :: String),
            "plan" Aeson..= plan
          ]
      SupervisorDetach ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("detach" :: String)
          ]
      SupervisorAcknowledgePin ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("acknowledge-pin" :: String)
          ]
      SupervisorOpenTargetGate ->
        Aeson.object
          [ "version" Aeson..= (2 :: Int),
            "request" Aeson..= ("open-target-gate" :: String)
          ]

instance Aeson.FromJSON SupervisorRequest where
  parseJSON =
    Aeson.withObject "SupervisorRequest" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (2 :: Int)) $
        fail "unsupported bounded-command supervisor-request version"
      request <- value Aeson..: "request"
      case request :: String of
        "configure" -> SupervisorConfigure <$> value Aeson..: "plan"
        "detach" -> pure SupervisorDetach
        "acknowledge-pin" -> pure SupervisorAcknowledgePin
        "open-target-gate" -> pure SupervisorOpenTargetGate
        _ -> fail "unknown bounded-command supervisor request"

instance Aeson.ToJSON SupervisorEvent where
  toJSON supervisorEvent =
    case supervisorEvent of
      SupervisorDetached supervisorIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("detached" :: String)
            ]
              <> identityJsonFields "supervisor" supervisorIdentity
          )
      SupervisorPinBorn pinIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("pin-born" :: String)
            ]
              <> provisionalIdentityJsonFields "pin" pinIdentity
          )
      SupervisorPrepared targetGroupLeaderIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("prepared" :: String)
            ]
              <> identityJsonFields "targetGroupLeader" targetGroupLeaderIdentity
          )
      SupervisorTerminal terminal inputEvidence stdoutEvidence stderrEvidence ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("terminal" :: String),
              "inputEvidence" Aeson..= inputEvidence,
              "stdoutEvidence" Aeson..= stdoutEvidence,
              "stderrEvidence" Aeson..= stderrEvidence
            ]
              <> terminalJsonFields terminal
          )

instance Aeson.FromJSON SupervisorEvent where
  parseJSON =
    Aeson.withObject "SupervisorEvent" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (3 :: Int)) $
        fail "unsupported bounded-command supervisor-event version"
      eventName <- value Aeson..: "event"
      case eventName :: String of
        "detached" ->
          SupervisorDetached
            <$> parsePrefixedIdentity value "supervisor"
        "pin-born" ->
          SupervisorPinBorn
            <$> parsePrefixedProvisionalIdentity value "pin"
        "prepared" ->
          SupervisorPrepared
            <$> parsePrefixedIdentity value "targetGroupLeader"
        "terminal" ->
          SupervisorTerminal
            <$> parseTargetTerminal value
            <*> value Aeson..: "inputEvidence"
            <*> value Aeson..: "stdoutEvidence"
            <*> value Aeson..: "stderrEvidence"
        _ -> fail "unknown bounded-command supervisor event"

instance Aeson.ToJSON PinRequest where
  toJSON request =
    case request of
      PinDetach ->
        Aeson.object
          [ "version" Aeson..= (1 :: Int),
            "request" Aeson..= ("detach" :: String)
          ]
      PinRetain ->
        Aeson.object
          [ "version" Aeson..= (1 :: Int),
            "request" Aeson..= ("retain" :: String)
          ]

instance Aeson.FromJSON PinRequest where
  parseJSON =
    Aeson.withObject "PinRequest" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (1 :: Int)) $
        fail "unsupported bounded-command executor-request version"
      request <- value Aeson..: "request"
      case request :: String of
        "detach" -> pure PinDetach
        "retain" -> pure PinRetain
        _ -> fail "unknown bounded-command pin request"

instance Aeson.ToJSON PinEvent where
  toJSON pinEvent =
    case pinEvent of
      PinTargetGroupReady targetGroupLeaderIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (1 :: Int),
              "event" Aeson..= ("target-group-ready" :: String)
            ]
              <> identityJsonFields "targetGroupLeader" targetGroupLeaderIdentity
          )
      PinRetained ->
        Aeson.object
          [ "version" Aeson..= (1 :: Int),
            "event" Aeson..= ("retained" :: String)
          ]

instance Aeson.FromJSON PinEvent where
  parseJSON =
    Aeson.withObject "PinEvent" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (1 :: Int)) $
        fail "unsupported bounded-command executor-event version"
      eventName <- value Aeson..: "event"
      case eventName :: String of
        "target-group-ready" ->
          PinTargetGroupReady
            <$> parsePrefixedIdentity value "targetGroupLeader"
        "retained" -> pure PinRetained
        _ -> fail "unknown bounded-command pin event"

instance Aeson.ToJSON SynchronousExceptionTreeEvidence where
  toJSON evidence =
    Aeson.object
      ( [ "version" Aeson..= (3 :: Int)
        ]
          <> identityJsonFields
            "target"
            (synchronousTargetIdentity evidence)
          <> identityJsonFields
            "descendant"
            (synchronousDescendantIdentity evidence)
          <> identityJsonFields
            "groupLeader"
            (synchronousGroupLeaderIdentity evidence)
      )

instance Aeson.FromJSON SynchronousExceptionTreeEvidence where
  parseJSON =
    Aeson.withObject "SynchronousExceptionTreeEvidence" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (3 :: Int)) $
        fail "unsupported bounded-command synchronous-exception evidence version"
      -- Only the retained pin is a group leader here. The target and its
      -- descendant are by construction non-leader members of that pin's
      -- group -- 'validateSynchronousExceptionTree' rejects the record unless
      -- both differ from the leader and share its process group -- so they
      -- decode through the group-member parser.
      SynchronousExceptionTreeEvidence
        <$> parsePrefixedMemberIdentity value "target"
        <*> parsePrefixedMemberIdentity value "descendant"
        <*> parsePrefixedIdentity value "groupLeader"

instance Aeson.ToJSON AnchorEvent where
  toJSON anchorEvent =
    case anchorEvent of
      AnchorSupervisorBorn supervisorIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("supervisor-born" :: String)
            ]
              <> provisionalIdentityJsonFields "supervisor" supervisorIdentity
          )
      AnchorPinBorn pinIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("pin-born" :: String)
            ]
              <> provisionalIdentityJsonFields "pin" pinIdentity
          )
      AnchorSupervisorReady supervisorIdentity targetGroupLeaderIdentity ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("supervisor-ready" :: String)
            ]
              <> identityJsonFields "supervisor" supervisorIdentity
              <> identityJsonFields "targetGroupLeader" targetGroupLeaderIdentity
          )
      AnchorTerminal supervisorExit terminal inputEvidence stdoutEvidence stderrEvidence ->
        Aeson.object
          ( [ "version" Aeson..= (3 :: Int),
              "event" Aeson..= ("terminal" :: String),
              "supervisorExit" Aeson..= renderExitCode supervisorExit,
              "inputEvidence" Aeson..= inputEvidence,
              "stdoutEvidence" Aeson..= stdoutEvidence,
              "stderrEvidence" Aeson..= stderrEvidence
            ]
              <> terminalJsonFields terminal
          )
      AnchorKernelFailure failure ->
        Aeson.object
          [ "version" Aeson..= (3 :: Int),
            "event" Aeson..= ("kernel-failure" :: String),
            "failure" Aeson..= failure
          ]

instance Aeson.FromJSON AnchorEvent where
  parseJSON =
    Aeson.withObject "AnchorEvent" $ \value -> do
      version <- value Aeson..: "version"
      unless (version == (3 :: Int)) $
        fail "unsupported bounded-command anchor-event version"
      eventName <- value Aeson..: "event"
      case eventName :: String of
        "supervisor-born" ->
          AnchorSupervisorBorn
            <$> parsePrefixedProvisionalIdentity value "supervisor"
        "pin-born" ->
          AnchorPinBorn
            <$> parsePrefixedProvisionalIdentity value "pin"
        "supervisor-ready" ->
          AnchorSupervisorReady
            <$> parsePrefixedIdentity value "supervisor"
            <*> parsePrefixedIdentity value "targetGroupLeader"
        "terminal" -> do
          renderedSupervisorExit <- value Aeson..: "supervisorExit"
          supervisorExit <-
            maybe
              (fail "invalid bounded-command supervisor exit evidence")
              pure
              (parseExitCode renderedSupervisorExit)
          AnchorTerminal
            supervisorExit
            <$> parseTargetTerminal value
            <*> value Aeson..: "inputEvidence"
            <*> value Aeson..: "stdoutEvidence"
            <*> value Aeson..: "stderrEvidence"
        "kernel-failure" -> AnchorKernelFailure <$> value Aeson..: "failure"
        _ -> fail "unknown bounded-command anchor event"

instance Aeson.ToJSON InputEvidence where
  toJSON inputEvidence =
    case inputEvidence of
      InputCompleted ->
        Aeson.object ["kind" Aeson..= ("completed" :: String)]
      InputFailed failure ->
        Aeson.object
          [ "kind" Aeson..= ("failed" :: String),
            "failure" Aeson..= failure
          ]

instance Aeson.FromJSON InputEvidence where
  parseJSON =
    Aeson.withObject "InputEvidence" $ \value -> do
      evidenceKind <- value Aeson..: "kind"
      case evidenceKind :: String of
        "completed" -> pure InputCompleted
        "failed" -> InputFailed <$> value Aeson..: "failure"
        _ -> fail "unknown bounded-command input evidence"

instance Aeson.ToJSON CaptureEvidence where
  toJSON captureEvidence =
    case captureEvidence of
      CaptureCompleted contents ->
        Aeson.object
          [ "kind" Aeson..= ("completed" :: String),
            "contentsBase64"
              Aeson..= TextEncoding.decodeUtf8 (Base64.encode contents)
          ]
      CaptureFailed failure ->
        Aeson.object
          [ "kind" Aeson..= ("failed" :: String),
            "failure" Aeson..= failure
          ]

instance Aeson.FromJSON CaptureEvidence where
  parseJSON =
    Aeson.withObject "CaptureEvidence" $ \value -> do
      evidenceKind <- value Aeson..: "kind"
      case evidenceKind :: String of
        "completed" -> do
          contentsBase64 <- value Aeson..: "contentsBase64"
          let encodedContents =
                TextEncoding.encodeUtf8 contentsBase64
          when
            (ByteString.length encodedContents > maximumEncodedCapturedOutputBytes)
            (fail "bounded-command capture exceeds its size limit")
          contents <-
            either
              (fail . ("invalid bounded-command capture base64: " <>))
              pure
              (Base64.decode encodedContents)
          when
            (ByteString.length contents > maximumCapturedOutputBytes)
            (fail "bounded-command capture exceeds its size limit")
          pure (CaptureCompleted contents)
        "failed" -> CaptureFailed <$> value Aeson..: "failure"
        _ -> fail "unknown bounded-command capture evidence"

identityJsonFields ::
  String ->
  ActivityProcessIdentity ->
  [Pair]
identityJsonFields prefix identity =
  [ AesonKey.fromString (prefix <> "ProcessId")
      Aeson..= activityProcessId identity,
    AesonKey.fromString (prefix <> "ProcessGroup")
      Aeson..= activityProcessGroup identity,
    AesonKey.fromString (prefix <> "BirthIdentity")
      Aeson..= renderProcessBirthIdentity
        (activityProcessBirthIdentity identity)
  ]

provisionalIdentityJsonFields ::
  String ->
  ProvisionalProcessIdentity ->
  [Pair]
provisionalIdentityJsonFields prefix identity =
  [ AesonKey.fromString (prefix <> "ProcessId")
      Aeson..= provisionalProcessId identity,
    AesonKey.fromString (prefix <> "ProcessGroup")
      Aeson..= provisionalProcessGroup identity,
    AesonKey.fromString (prefix <> "BirthIdentity")
      Aeson..= renderProcessBirthIdentity
        (provisionalBirthIdentity identity)
  ]

parsePrefixedIdentity ::
  Object ->
  String ->
  Parser ActivityProcessIdentity
parsePrefixedIdentity value prefix =
  parseActivityProcessIdentity
    value
    (AesonKey.fromString (prefix <> "ProcessId"))
    (AesonKey.fromString (prefix <> "ProcessGroup"))
    (AesonKey.fromString (prefix <> "BirthIdentity"))

parsePrefixedMemberIdentity ::
  Object ->
  String ->
  Parser ActivityProcessIdentity
parsePrefixedMemberIdentity value prefix =
  parseActivityIdentity
    value
    (AesonKey.fromString (prefix <> "ProcessId"))
    (AesonKey.fromString (prefix <> "ProcessGroup"))
    (AesonKey.fromString (prefix <> "BirthIdentity"))

parsePrefixedProvisionalIdentity ::
  Object ->
  String ->
  Parser ProvisionalProcessIdentity
parsePrefixedProvisionalIdentity value prefix = do
  identity <-
    parseActivityIdentity
      value
      (AesonKey.fromString (prefix <> "ProcessId"))
      (AesonKey.fromString (prefix <> "ProcessGroup"))
      (AesonKey.fromString (prefix <> "BirthIdentity"))
  pure (provisionalFromActivityIdentity identity)

terminalJsonFields :: TargetTerminal -> [Pair]
terminalJsonFields terminal =
  case terminal of
    TargetExited exitCode ->
      [ "terminalKind" Aeson..= ("exited" :: String),
        "exitCode" Aeson..= exitCode
      ]
    TargetSignaled signal coreDumped ->
      [ "terminalKind" Aeson..= ("signaled" :: String),
        "signal" Aeson..= signal,
        "coreDumped" Aeson..= coreDumped
      ]
    TargetKernelFailure failure ->
      [ "terminalKind" Aeson..= ("kernel" :: String),
        "failure" Aeson..= failure
      ]

parseTargetTerminal :: Object -> Parser TargetTerminal
parseTargetTerminal value = do
  terminalKind <- value Aeson..: "terminalKind"
  case terminalKind :: String of
    "exited" -> do
      exitCode <- value Aeson..: "exitCode"
      if exitCode >= 0 && exitCode <= maximumProtocolExitCode
        then pure (TargetExited exitCode)
        else fail "invalid bounded-command target exit evidence"
    "signaled" -> do
      signal <- value Aeson..: "signal"
      if signal > 0 && signal <= maximumProtocolSignalNumber
        then TargetSignaled signal <$> value Aeson..: "coreDumped"
        else fail "invalid bounded-command target signal evidence"
    "kernel" -> TargetKernelFailure <$> value Aeson..: "failure"
    _ -> fail "unknown bounded-command terminal kind"

renderExitCode :: ExitCode -> Int
renderExitCode ExitSuccess = 0
renderExitCode (ExitFailure exitCode) = exitCode

parseExitCode :: Int -> Maybe ExitCode
parseExitCode 0 = Just ExitSuccess
parseExitCode exitCode
  | exitCode > 0 && exitCode <= maximumProtocolExitCode =
      Just (ExitFailure exitCode)
  | otherwise = Nothing

data TrackedHelper = TrackedHelper
  { trackedHelperProcessId :: !ProcessID,
    trackedHelperIdentity :: !ActivityProcessIdentity,
    trackedHelperHandle :: !ProcessHandle,
    trackedHelperExitCode :: !(MVar (Maybe ExitCode))
  }

data SpawnedHelper = SpawnedHelper
  { spawnedHelperInput :: !Handle,
    spawnedHelperOutput :: !Handle,
    spawnedHelperError :: !Handle,
    spawnedHelperTracked :: !TrackedHelper
  }

data HelperProcessGroup
  = CreateHelperProcessGroup
  | InheritHelperProcessGroup

data SupervisedSession = SupervisedSession
  { supervisedAnchorControl :: !Protocol.AnchorControl,
    supervisedAnchorOutput :: !Handle,
    supervisedAnchorErrorResult ::
      !(MVar (Either SomeException ByteString.ByteString)),
    supervisedAnchor :: !TrackedHelper,
    supervisedSupervisorProvisional ::
      !(MVar (Maybe ProvisionalProcessIdentity)),
    supervisedSupervisorIdentity ::
      !(MVar (Maybe ActivityProcessIdentity)),
    supervisedPinProvisional ::
      !(MVar (Maybe ProvisionalProcessIdentity)),
    supervisedTargetGroupLeaderIdentity ::
      !(MVar (Maybe ActivityProcessIdentity)),
    supervisedPublishedActivity ::
      !(MVar (Maybe PublishedCommandActivity))
  }

data ProtocolReport
  = ProtocolTerminal
      !ExitCode
      !TargetTerminal
      !InputEvidence
      !CaptureEvidence
      !CaptureEvidence
  | ProtocolKernelFailure !String
  deriving (Eq, Show)

spawnSelfExecHelper ::
  [(String, String)] ->
  String ->
  IO SpawnedHelper
spawnSelfExecHelper =
  spawnSelfExecHelperWithGroup CreateHelperProcessGroup

spawnSelfExecHelperWithGroup ::
  HelperProcessGroup ->
  [(String, String)] ->
  String ->
  IO SpawnedHelper
spawnSelfExecHelperWithGroup helperGroup explicitEnvironment mode =
  mask_ (spawnSelfExecHelperMasked helperGroup explicitEnvironment mode)

spawnSelfExecHelperMasked ::
  HelperProcessGroup ->
  [(String, String)] ->
  String ->
  IO SpawnedHelper
spawnSelfExecHelperMasked helperGroup explicitEnvironment mode = do
  unless (validExplicitEnvironment explicitEnvironment) $
    ioError (userError "bounded-command helper environment is invalid")
  -- A bounded command performs three self-exec spawns (anchor, supervisor,
  -- target), each of which closes every descriptor up to the soft
  -- RLIMIT_NOFILE before 'exec'. Unbounded, that is a quarter-hour per command
  -- inside a containerd pod. See "Infernix.DescriptorSpace".
  _ <- requireBoundedDescriptorSpace "bounded-command self-exec helper"
  executable <- getExecutablePath
  created <-
    createProcess
      (proc executable [mode])
        { std_in = CreatePipe,
          std_out = CreatePipe,
          std_err = CreatePipe,
          cwd = Nothing,
          env = Just explicitEnvironment,
          close_fds = True,
          create_group =
            case helperGroup of
              CreateHelperProcessGroup -> True
              InheritHelperProcessGroup -> False
        }
  let (maybeInput, maybeOutput, maybeError, processHandle) = created
      closeCreatedHandles =
        runCleanupsPreservingFailures
          ( map
              (maybe (pure ()) (ignoreIOException . hClose))
              [maybeInput, maybeOutput, maybeError]
          )
      terminateCreated =
        do
          maybeProcessId <- getPid processHandle
          let signalCreated processId =
                case helperGroup of
                  CreateHelperProcessGroup ->
                    runCleanupsPreservingFailures
                      [ ignoreIOException
                          (signalProcessGroup sigCONT (fromIntegral processId)),
                        ignoreIOException (signalProcess sigCONT processId),
                        ignoreIOException
                          (signalProcessGroup sigKILL (fromIntegral processId)),
                        ignoreIOException (signalProcess sigKILL processId)
                      ]
                  InheritHelperProcessGroup ->
                    runCleanupsPreservingFailures
                      [ ignoreIOException (signalProcess sigCONT processId),
                        ignoreIOException (signalProcess sigKILL processId)
                      ]
              proveCreatedAbsent processId =
                case helperGroup of
                  CreateHelperProcessGroup ->
                    awaitUnregisteredProcessGroupAbsent
                      "new self-exec helper"
                      processId
                      500
                  InheritHelperProcessGroup ->
                    awaitUnregisteredProcessAbsent
                      "new self-exec helper"
                      processId
                      500
          runCleanupsPreservingFailures
            ( maybe [] (pure . signalCreated) maybeProcessId
                <> [void (waitForProcessBounded processHandle)]
                <> maybe [] (pure . proveCreatedAbsent) maybeProcessId
                <> [closeCreatedHandles]
            )
      createdStandardStreams =
        case (maybeInput, maybeOutput, maybeError) of
          (Just inputValue, Just outputValue, Just errorValue) ->
            pure (inputValue, outputValue, errorValue)
          _ ->
            ioError
              (userError "bounded-command helper did not expose all standard-stream pipes")
  (inputHandle, outputHandle, errorHandle) <-
    onExceptionPreservingPrimary
      createdStandardStreams
      terminateCreated
  onExceptionPreservingPrimary
    (mapM_ prepareProtocolHandle [inputHandle, outputHandle, errorHandle])
    terminateCreated
  processId <-
    onExceptionPreservingPrimary
      ( do
          maybeProcessId <- getPid processHandle
          maybe
            (ioError (userError "bounded-command helper exited before identity publication"))
            pure
            maybeProcessId
      )
      terminateCreated
  HelperIdentityReady helperIdentity <-
    onExceptionPreservingPrimary
      ( readJsonFrameHandle
          "helper identity"
          outputHandle
      )
      terminateCreated
  onExceptionPreservingPrimary
    ( do
        unless
          (activityProcessId helperIdentity == fromIntegral processId)
          ( ioError
              (userError "bounded-command helper identity disagreed with ProcessHandle")
          )
        case helperGroup of
          CreateHelperProcessGroup ->
            unless
              (activityProcessGroup helperIdentity == activityProcessId helperIdentity)
              ( ioError
                  (userError "bounded-command helper process group is invalid")
              )
          InheritHelperProcessGroup -> pure ()
        validateObservedGroupMember
          "self-exec helper"
          helperIdentity
    )
    terminateCreated
  exitCodeState <-
    onExceptionPreservingPrimary
      (newMVar Nothing)
      terminateCreated
  pure
    SpawnedHelper
      { spawnedHelperInput = inputHandle,
        spawnedHelperOutput = outputHandle,
        spawnedHelperError = errorHandle,
        spawnedHelperTracked =
          TrackedHelper
            { trackedHelperProcessId = processId,
              trackedHelperIdentity = helperIdentity,
              trackedHelperHandle = processHandle,
              trackedHelperExitCode = exitCodeState
            }
      }

prepareProtocolHandle :: Handle -> IO ()
prepareProtocolHandle handle = do
  hSetBinaryMode handle True
  hSetBuffering handle NoBuffering

pollTrackedHelper :: TrackedHelper -> IO (Maybe ExitCode)
pollTrackedHelper tracked =
  modifyMVar (trackedHelperExitCode tracked) $ \cachedExit ->
    case cachedExit of
      Just exitCode -> pure (cachedExit, Just exitCode)
      Nothing -> do
        maybeExitCode <- getProcessExitCode (trackedHelperHandle tracked)
        pure (maybeExitCode, maybeExitCode)

waitForTrackedHelperMaybe :: TrackedHelper -> IO (Maybe ExitCode)
waitForTrackedHelperMaybe tracked = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.pollLimitedDeadline 10000 1 1 101)
      pollHelper
  pure
    ( Readiness.foldReadiness
        Just
        (const Nothing)
        (const Nothing)
        outcome
    )
  where
    pollHelper = do
      maybeExitCode <- pollTrackedHelper tracked
      pure
        ( maybe
            (Left (Readiness.Progress 0 1 "waiting for owned helper exit"))
            Right
            maybeExitCode
        )

waitForTrackedHelperBounded :: TrackedHelper -> IO ExitCode
waitForTrackedHelperBounded tracked = do
  maybeExitCode <- waitForTrackedHelperMaybe tracked
  maybe
    ( ioError
        ( userError
            ( "runBoundedCommand: timed out reaping owned helper pid "
                <> show (trackedHelperProcessId tracked)
            )
        )
    )
    pure
    maybeExitCode

waitForProcessBounded :: ProcessHandle -> IO ExitCode
waitForProcessBounded processHandle = do
  result <- timeout 1000000 (waitForProcess processHandle)
  maybe
    (ioError (userError "bounded-command helper reap exceeded its cleanup deadline"))
    pure
    result

awaitUnregisteredProcessGroupAbsent ::
  String ->
  ProcessID ->
  Int ->
  IO ()
awaitUnregisteredProcessGroupAbsent label processGroup =
  awaitUnregisteredKernelIdentityAbsent
    (label <> " process group")
    (signalProcessGroup nullSignal (fromIntegral processGroup))

awaitUnregisteredProcessAbsent ::
  String ->
  ProcessID ->
  Int ->
  IO ()
awaitUnregisteredProcessAbsent label processId =
  awaitUnregisteredKernelIdentityAbsent
    (label <> " process")
    (signalProcess nullSignal processId)

awaitUnregisteredKernelIdentityAbsent ::
  String ->
  IO () ->
  Int ->
  IO ()
awaitUnregisteredKernelIdentityAbsent label probeAction attemptsRemaining = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.budgetDeadline attemptsRemaining 10000)
      probe
  Readiness.foldReadiness
    pure
    (const (ioError timeoutFailure))
    (const (ioError timeoutFailure))
    outcome
  where
    probe = do
      result <- try @IOException probeAction
      case result of
        Left failure
          | isDoesNotExistError failure -> pure (Right ())
          -- EPERM is not absence, and it is not a reason to abandon the proof
          -- either. Darwin reports it while a just-exited group still holds
          -- unreaped kernel state, and Linux reports it while one surviving
          -- member belongs to a uid we may not signal. Both resolve to ESRCH
          -- once the group is really gone, so keep polling until it does or
          -- until the bounded budget runs out. Only ESRCH ever discharges the
          -- obligation; a persistent EPERM still fails closed below.
          | isPermissionError failure -> pure stillPresent
          | otherwise -> ioError failure
        Right () -> pure stillPresent
    stillPresent =
      Left
        Readiness.Progress
          { Readiness.progressObserved = 0,
            Readiness.progressExpected = 1,
            Readiness.progressDetail =
              Text.pack ("still live: " <> label)
          }
    timeoutFailure =
      userError
        ("bounded-command cleanup could not prove absent: " <> label)

closeSpawnedHelperHandles :: SpawnedHelper -> IO ()
closeSpawnedHelperHandles helper =
  runCleanupsPreservingFailures
    [ ignoreIOException (hClose (spawnedHelperInput helper)),
      ignoreIOException (hClose (spawnedHelperOutput helper)),
      ignoreIOException (hClose (spawnedHelperError helper))
    ]

-- | Drive 'signalActivityProcessGroupWith' against a recorded identity built
-- from raw kernel observations.
--
-- The identity is assembled here rather than by the caller so the regression
-- suite gains no constructor for 'ActivityProcessIdentity'.
signalActivityProcessGroupForTest ::
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO ()
signalActivityProcessGroupForTest processId processGroup birthIdentity =
  signalActivityProcessGroupWith
    sigKILL
    (ActivityProcessIdentity processId processGroup birthIdentity)

-- | Observe one recorded group the way abandoned-activity recovery does, and
-- report whether it classified as active. A refusal still throws.
observeRecoverableProcessGroupActiveForTest ::
  Integer ->
  Integer ->
  ProcessBirthIdentity ->
  IO Bool
observeRecoverableProcessGroupActiveForTest
  processId
  processGroup
  birthIdentity = do
    (_, _, status) <-
      observeRecoverableProcessGroup
        ( "regression",
          ActivityProcessIdentity processId processGroup birthIdentity
        )
    pure (recoverableProcessGroupIsActive status)

recoverableProcessGroupIsActive :: RecoverableProcessGroupStatus -> Bool
recoverableProcessGroupIsActive status =
  case status of
    RecoverableProcessGroupActive -> True
    RecoverableProcessGroupAbsent -> False

signalActivityProcessGroupWith ::
  Signal ->
  ActivityProcessIdentity ->
  IO ()
signalActivityProcessGroupWith signal identity = do
  unless
    (activityProcessId identity == activityProcessGroup identity)
    ( ioError
        ( userError
            "bounded-command refused to signal a group without its leader identity"
        )
    )
  observedBirthIdentity <-
    readProcessBirthIdentity (activityProcessId identity)
  case observedBirthIdentity of
    -- The exact leader was already gone when this signal was requested. That
    -- is the ordinary shape while a designated owner reaps the leader and the
    -- rest of the group is still exiting, not evidence of reuse: a live group
    -- whose leader PID is unallocated cannot have been re-created under that
    -- id. Its group id can no longer be vouched for, so nothing is signalled;
    -- the group must instead become absent within the bounded window, which is
    -- the same evidence the successful-signal path would have had to obtain.
    Nothing -> requireActivityGroupAbsentAfterLeaderLookupFailure identity
    Just observedIdentity
      | observedIdentity /= activityProcessBirthIdentity identity ->
          ioError
            ( userError
                "bounded-command refused to signal a process group with a mismatched leader birth identity"
            )
      | otherwise -> do
          observedProcessGroupResult <-
            try @IOException
              (getProcessGroupIDOf (fromIntegral (activityProcessId identity)))
          case observedProcessGroupResult of
            Left failure
              | isDoesNotExistError failure ->
                  requireActivityGroupAbsentAfterLeaderLookupFailure identity
              | otherwise -> ioError failure
            Right observedProcessGroup -> do
              observedBirthIdentityAfter <-
                readProcessBirthIdentity (activityProcessId identity)
              case observedBirthIdentityAfter of
                -- The designated owner reaped the exact leader between this
                -- signal's identity check and its group lookup. An absent
                -- leader is not a mismatched leader, and only the second is
                -- the reuse this refusal exists for.
                Nothing ->
                  requireActivityGroupAbsentAfterLeaderLookupFailure identity
                Just laterIdentity
                  | laterIdentity /= activityProcessBirthIdentity identity ->
                      ioError
                        ( userError
                            "bounded-command refused to signal a process group with a mismatched leader birth identity"
                        )
                  | fromIntegral observedProcessGroup
                      /= activityProcessGroup identity ->
                      ioError
                        ( userError
                            "bounded-command refused to signal an unstable process-group identity"
                        )
                  | otherwise -> do
                      result <-
                        try @IOException
                          ( signalProcessGroup
                              signal
                              (fromIntegral (activityProcessGroup identity))
                          )
                      case result of
                        Right () -> pure ()
                        Left failure
                          | isDoesNotExistError failure -> pure ()
                          | otherwise -> ioError failure

requireActivityGroupAbsentAfterLeaderLookupFailure ::
  ActivityProcessIdentity ->
  IO ()
requireActivityGroupAbsentAfterLeaderLookupFailure identity = do
  observedBirthIdentityAfter <-
    readProcessBirthIdentity (activityProcessId identity)
  case observedBirthIdentityAfter of
    Just observedIdentity
      | observedIdentity /= activityProcessBirthIdentity identity ->
          ioError
            ( userError
                "bounded-command refused a reused leader after group lookup failed"
            )
    _ -> pure ()
  -- The exact leader was reaped by its designated owner between this signal's
  -- identity check and its group lookup. That owner is still tearing the rest
  -- of the group down, so demanding instantaneous absence would race it.
  -- Signalling the bare process-group id is still refused, because a reaped
  -- leader can no longer prove the group id was not reused; instead the group
  -- must become absent within the bounded cleanup window, which is the same
  -- evidence the caller would otherwise have obtained.
  awaitUnregisteredProcessGroupAbsent
    "reaped-leader activity group"
    (fromIntegral (activityProcessGroup identity))
    leaderlessGroupAbsenceAttempts

-- | Poll budget, at the shared 10ms interval, for a group whose exact leader
-- was reaped while its designated owner was still terminating the members.
leaderlessGroupAbsenceAttempts :: Int
leaderlessGroupAbsenceAttempts = 500

signalActivityProcessWith ::
  Signal ->
  ActivityProcessIdentity ->
  IO ()
signalActivityProcessWith signal identity = do
  let processId = activityProcessId identity
  observedBirthIdentity <-
    readProcessBirthIdentity processId
  case observedBirthIdentity of
    Just observedIdentity
      | observedIdentity == activityProcessBirthIdentity identity ->
          ignoreMissing
            (signalProcess signal (fromIntegral processId))
      | otherwise ->
          ioError
            ( userError
                ( "bounded-command refused to signal reused pid "
                    <> show processId
                )
            )
    Nothing ->
      ignoreMissing
        (signalProcess nullSignal (fromIntegral processId))
  where
    ignoreMissing action = do
      outcome <- try @IOException action
      case outcome of
        Right () -> pure ()
        Left failure
          | isDoesNotExistError failure -> pure ()
          | otherwise -> ioError failure

signalProvisionalProcessWith ::
  Signal ->
  ProvisionalProcessIdentity ->
  IO ()
signalProvisionalProcessWith signal identity = do
  let processId = provisionalProcessId identity
      initialGroup = provisionalProcessGroup identity
  observedBirthIdentity <-
    readProcessBirthIdentity processId
  case observedBirthIdentity of
    Just observedIdentity
      | observedIdentity /= provisionalBirthIdentity identity ->
          ioError
            (userError "bounded-command refused to signal a reused provisional pid")
      | otherwise -> do
          observedGroupResult <-
            try @IOException (getProcessGroupIDOf (fromIntegral processId))
          case observedGroupResult of
            Left failure
              -- The exact process was reaped between the identity check and
              -- its group lookup. That is the same ordinary shape the activity
              -- signaller handles, not an unattributed kernel error.
              | isDoesNotExistError failure ->
                  requireProvisionalAbsent identity
              | otherwise -> ioError failure
            Right rawGroup -> do
              let observedGroup = fromIntegral rawGroup
              observedBirthIdentityAfter <-
                readProcessBirthIdentity processId
              case observedBirthIdentityAfter of
                -- Gone is not reused. Only a *different* birth identity is
                -- the recycled pid this refusal exists for.
                Nothing -> requireProvisionalAbsent identity
                Just laterIdentity
                  | laterIdentity /= provisionalBirthIdentity identity ->
                      ioError
                        ( userError
                            "bounded-command refused to signal an unstable provisional process identity"
                        )
                  | observedGroup == processId ->
                      signalKnownGroup processId
                  | observedGroup == initialGroup ->
                      signalKnownProcess processId
                  | otherwise ->
                      ioError
                        ( userError
                            "bounded-command provisional process made an unauthorized group transition"
                        )
    Nothing ->
      requireProvisionalAbsent identity
  where
    signalKnownGroup processGroup =
      ignoreMissing
        (signalProcessGroup signal (fromIntegral processGroup))
    signalKnownProcess processId =
      ignoreMissing
        (signalProcess signal (fromIntegral processId))
    ignoreMissing action = do
      outcome <- try @IOException action
      case outcome of
        Right () -> pure ()
        Left failure
          | isDoesNotExistError failure -> pure ()
          | otherwise -> ioError failure

-- | The provisional counterpart of
-- 'requireActivityGroupAbsentAfterLeaderLookupFailure'.
--
-- Nothing is signalled once the exact provisional process is gone: its pid can
-- no longer vouch for the group id, so the obligation is discharged by proving
-- absence within the bounded window instead. A reused pid is still refused,
-- and the group half runs only when the recorded identity was its own group
-- leader — probing a non-leader pid as a process-group id would be exactly the
-- bare-PGID assumption this kernel forbids.
requireProvisionalAbsent ::
  ProvisionalProcessIdentity ->
  IO ()
requireProvisionalAbsent identity = do
  observedBirthIdentityAfter <-
    readProcessBirthIdentity (provisionalProcessId identity)
  case observedBirthIdentityAfter of
    Just observedIdentity
      | observedIdentity /= provisionalBirthIdentity identity ->
          ioError
            ( userError
                "bounded-command refused a reused provisional pid after its exact process disappeared"
            )
    _ -> pure ()
  awaitUnregisteredProcessAbsent
    "reaped provisional"
    (fromIntegral (provisionalProcessId identity))
    leaderlessGroupAbsenceAttempts
  when
    (provisionalProcessGroup identity == provisionalProcessId identity)
    ( awaitUnregisteredProcessGroupAbsent
        "reaped provisional group"
        (fromIntegral (provisionalProcessGroup identity))
        leaderlessGroupAbsenceAttempts
    )

signalActivityProcessGroup ::
  ActivityProcessIdentity ->
  IO ()
signalActivityProcessGroup =
  signalActivityProcessGroupWith sigKILL

-- | Signal a helper-owned group before the designated owner reaps its leader.
-- The unreaped 'ProcessHandle' prevents PID reuse even after the helper has
-- exited, so the recorded group remains attributable while descendants are
-- terminated.
signalOwnedUnreapedHelperGroupWith ::
  Signal ->
  TrackedHelper ->
  ActivityProcessIdentity ->
  IO ()
signalOwnedUnreapedHelperGroupWith signal tracked finalIdentity = do
  cachedExit <- readMVar (trackedHelperExitCode tracked)
  unless (isNothing cachedExit) $
    ioError
      (userError "bounded-command refused to signal a helper group after leader reap")
  let spawnedIdentity = trackedHelperIdentity tracked
  unless
    ( activityProcessId spawnedIdentity == activityProcessId finalIdentity
        && activityProcessBirthIdentity spawnedIdentity
          == activityProcessBirthIdentity finalIdentity
        && activityProcessId finalIdentity
          == activityProcessGroup finalIdentity
    )
    (ioError (userError "bounded-command helper group ownership evidence is invalid"))
  result <-
    try @IOException
      ( signalProcessGroup
          signal
          (fromIntegral (activityProcessGroup finalIdentity))
      )
  case result of
    Right () -> pure ()
    Left failure
      | isDoesNotExistError failure -> pure ()
      | otherwise -> ioError failure

signalOwnedUnreapedProcessWith ::
  Signal ->
  TrackedProcess ->
  IO ()
signalOwnedUnreapedProcessWith signal tracked = do
  cachedStatus <- readMVar (trackedProcessStatus tracked)
  unless (isNothing cachedStatus) $
    ioError
      (userError "bounded-command refused to signal a target after its designated reap")
  validateObservedGroupMember
    "owned target"
    (trackedProcessIdentity tracked)
  signalActivityProcessWith signal (trackedProcessIdentity tracked)

writeJsonFrameHandle ::
  (Aeson.ToJSON value) =>
  Handle ->
  value ->
  IO ()
writeJsonFrameHandle handle =
  writeFrameHandle handle . LazyByteString.toStrict . Aeson.encode

readJsonFrameHandle ::
  (Aeson.FromJSON value) =>
  String ->
  Handle ->
  IO value
readJsonFrameHandle label handle = do
  encoded <- readFrameHandle handle
  either
    ( \failure ->
        ioError
          ( userError
              ("invalid bounded-command " <> label <> " frame: " <> failure)
          )
    )
    pure
    (Aeson.eitherDecodeStrict' encoded)

writeJsonFrameFd ::
  (Aeson.ToJSON value) =>
  Fd ->
  value ->
  IO ()
writeJsonFrameFd descriptor value =
  encodeJsonFrame value >>= writeFdFully descriptor

-- | The regular-file counterpart of 'writeJsonFrameFd'.
--
-- The write side needs the same split the read side already draws between
-- 'readRegularFdChunk' and 'readFdChunk'. 'writeFdFully' waits on the IO
-- manager first, and a regular file cannot be registered with it: @epoll_ctl@
-- answers @EPERM@ for one, so the wait fails before any byte is written.
-- Darwin's kqueue accepts a regular-file registration, which is why a
-- descriptor published this way worked there and could not work on Linux. A
-- regular-file write never reports @EAGAIN@, so there is nothing for the wait
-- to do in either case.
writeRegularJsonFrameFd ::
  (Aeson.ToJSON value) =>
  Fd ->
  value ->
  IO ()
writeRegularJsonFrameFd descriptor value =
  encodeJsonFrame value >>= writeFdFullyBlocking descriptor

encodeJsonFrame ::
  (Aeson.ToJSON value) =>
  value ->
  IO ByteString.ByteString
encodeJsonFrame value = do
  let payload = LazyByteString.toStrict (Aeson.encode value)
  when
    (ByteString.length payload > maximumTargetSetupFrameBytes)
    (ioError (userError "bounded-command target-setup frame exceeds its size limit"))
  let rawLength = showHex (ByteString.length payload) ""
      header =
        ByteString8.pack
          (replicate (8 - length rawLength) '0' <> rawLength <> "\n")
  pure (header <> payload)

readJsonFrameFd ::
  (Aeson.FromJSON value) =>
  String ->
  Fd ->
  IO value
readJsonFrameFd label descriptor = do
  header <- readFdExactly descriptor 9
  let (hexLength, newline) = ByteString8.splitAt 8 header
      parsedLength =
        case readHex (ByteString8.unpack hexLength) of
          [(value, "")] -> Just value
          _ -> Nothing
  frameLength <-
    case (parsedLength, newline) of
      (Just value, suffix)
        | suffix == ByteString8.pack "\n",
          value >= 0,
          value <= maximumTargetSetupFrameBytes ->
            pure value
      _ ->
        ioError (userError "invalid bounded-command target-setup frame header")
  encoded <- readFdExactly descriptor frameLength
  either
    ( \failure ->
        ioError
          ( userError
              ( "invalid bounded-command "
                  <> label
                  <> " frame: "
                  <> failure
              )
          )
    )
    pure
    (Aeson.eitherDecodeStrict' encoded)

writeFrameHandle ::
  Handle ->
  ByteString.ByteString ->
  IO ()
writeFrameHandle handle payload
  | ByteString.length payload > maximumSupervisorFrameBytes =
      ioError (userError "bounded-command protocol frame exceeds its size limit")
  | otherwise = do
      let rawLength = showHex (ByteString.length payload) ""
          header =
            ByteString8.pack
              (replicate (8 - length rawLength) '0' <> rawLength <> "\n")
      ByteString.hPut handle header
      ByteString.hPut handle payload
      hFlush handle

readFrameHandle :: Handle -> IO ByteString.ByteString
readFrameHandle handle = do
  header <- readHandleExactly handle 9
  let (hexLength, newline) = ByteString8.splitAt 8 header
      parsedLength =
        case readHex (ByteString8.unpack hexLength) of
          [(value, "")] -> Just value
          _ -> Nothing
  frameLength <-
    case (parsedLength, newline) of
      (Just value, suffix)
        | suffix == ByteString8.pack "\n",
          value >= 0,
          value <= maximumSupervisorFrameBytes ->
            pure value
      _ ->
        ioError (userError "invalid bounded-command protocol frame header")
  readHandleExactly handle frameLength

readHandleExactly ::
  Handle ->
  Int ->
  IO ByteString.ByteString
readHandleExactly handle requestedBytes =
  go requestedBytes []
  where
    go remaining chunks
      | remaining <= 0 = pure (ByteString.concat (reverse chunks))
      | otherwise = do
          contents <- ByteString.hGet handle remaining
          if ByteString.null contents
            then
              ioError (userError "truncated bounded-command protocol frame")
            else
              go
                (remaining - ByteString.length contents)
                (contents : chunks)

readFdExactly :: Fd -> Int -> IO ByteString.ByteString
readFdExactly descriptor requestedBytes =
  go requestedBytes []
  where
    go remaining chunks
      | remaining <= 0 =
          pure (ByteString.concat (reverse chunks))
      | otherwise = do
          contents <- readFdChunk descriptor remaining
          if ByteString.null contents
            then ioError (userError "truncated bounded-command target-setup frame")
            else
              go
                (remaining - ByteString.length contents)
                (contents : chunks)

readJsonFrameBefore ::
  (Aeson.FromJSON value) =>
  Word64 ->
  String ->
  Handle ->
  IO value
readJsonFrameBefore deadline label handle =
  runActionBeforeDeadline
    deadline
    (readJsonFrameHandle label handle)

runActionBeforeDeadline :: Word64 -> IO value -> IO value
runActionBeforeDeadline deadline action = do
  remaining <- remainingDeadlineMicros deadline
  if remaining <= 0
    then deadlineExpired
    else timeout remaining action >>= maybe deadlineExpired pure
  where
    deadlineExpired =
      ioError (userError "bounded-command attempt deadline expired")

acquireSupervisedSession ::
  BoundedCommand command ->
  IO SupervisedSession
acquireSupervisedSession command = mask $ \restore -> do
  anchor <-
    spawnSelfExecHelper
      (renderSubprocessEnv (boundedEnvironment command))
      internalAnchorMode
  let trackedAnchor = spawnedHelperTracked anchor
      stopAnchor =
        runCleanupsPreservingFailures
          [ ignoreIOException
              ( signalOwnedUnreapedHelperGroupWith
                  sigCONT
                  trackedAnchor
                  (trackedHelperIdentity trackedAnchor)
              ),
            ignoreIOException
              ( signalOwnedUnreapedHelperGroupWith
                  sigKILL
                  trackedAnchor
                  (trackedHelperIdentity trackedAnchor)
              ),
            ignoreIOException (hClose (spawnedHelperInput anchor)),
            void (waitForTrackedHelperBounded trackedAnchor),
            awaitRecordedProcessGroupAbsent
              "acquisition anchor"
              (trackedHelperIdentity trackedAnchor)
              500,
            closeSpawnedHelperHandles anchor
          ]
  onExceptionPreservingPrimary
    ( restore $ do
        runAcquisitionDeadlineTestHook
          (trackedHelperIdentity trackedAnchor)
          (boundedCommandIdentity command)
        errorResult <- newEmptyMVar
        void
          ( forkIO
              ( drainHandle
                  maximumHelperDiagnosticBytes
                  (spawnedHelperError anchor)
                  errorResult
              )
          )
        supervisorIdentity <- newMVar Nothing
        supervisorProvisional <- newMVar Nothing
        pinProvisional <- newMVar Nothing
        targetGroupLeaderIdentity <- newMVar Nothing
        published <- newMVar Nothing
        pure
          SupervisedSession
            { supervisedAnchorControl =
                Protocol.encloseAnchorControl (spawnedHelperInput anchor),
              supervisedAnchorOutput = spawnedHelperOutput anchor,
              supervisedAnchorErrorResult = errorResult,
              supervisedAnchor = trackedAnchor,
              supervisedSupervisorProvisional = supervisorProvisional,
              supervisedSupervisorIdentity = supervisorIdentity,
              supervisedPinProvisional = pinProvisional,
              supervisedTargetGroupLeaderIdentity = targetGroupLeaderIdentity,
              supervisedPublishedActivity = published
            }
    )
    stopAnchor

runAcquisitionDeadlineTestHook ::
  ActivityProcessIdentity ->
  CommandIdentity ->
  IO ()
runAcquisitionDeadlineTestHook anchorIdentity identity =
  case acquisitionDeadlineTestReadyPath identity of
    Nothing -> pure ()
    Just readyPath -> do
      ByteString8.writeFile
        readyPath
        ( ByteString8.pack
            ( show (activityProcessId anchorIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity anchorIdentity)
                <> "\n"
            )
        )
      deadlineGate <- newEmptyMVar :: IO (MVar ())
      takeMVar deadlineGate

runSupervisedAttempt ::
  BoundedCommand command ->
  Word64 ->
  IO AttemptOutcome
runSupervisedAttempt command attemptDeadline = mask $ \restore -> do
  acquisition <-
    try @SomeException
      ( runActionBeforeDeadline
          attemptDeadline
          (acquireSupervisedSession command)
      )
  case acquisition of
    Left failure ->
      case fromException failure :: Maybe SomeAsyncException of
        Just _ -> throwIO failure
        Nothing
          | "attempt deadline expired" `List.isInfixOf` displayException failure ->
              pure AttemptTimedOut
          | otherwise ->
              pure
                ( AttemptKernelFailure
                    ("runBoundedCommand: " <> displayException failure)
                )
    Right session ->
      onExceptionPreservingPrimary
        ( do
            protocol <-
              try @IOException
                (restore (runSupervisorProtocol command session attemptDeadline))
            mask_ $ do
              cleanup <-
                cleanupSupervisedProcesses
                  command
                  session
                  (anchorShutdownExpectation protocol)
              diagnostic <-
                takeMVarBounded
                  "anchor stderr capture"
                  (supervisedAnchorErrorResult session)
              pure
                ( finalizeSupervisedAttempt
                    (boundedCommandIdentity command)
                    ( subprocessEnvRuntimeRoot (boundedEnvironment command)
                        </> "command-executable-snapshots"
                    )
                    protocol
                    cleanup
                    diagnostic
                )
        )
        ( mask_ $ do
            cleanup <-
              cleanupSupervisedProcesses
                command
                session
                TerminateAnchorNow
            either
              (ioError . userError)
              (const (pure ()))
              cleanup
        )

withSynchronousExceptionFifo ::
  CommandIdentity ->
  IO value ->
  IO value
withSynchronousExceptionFifo identity action =
  case synchronousExceptionPaths identity of
    Nothing -> action
    Just (_, releaseFifo) -> mask $ \restore -> do
      let readerReadyPath =
            synchronousExceptionReaderReadyPath releaseFifo
      mapM_
        requireSynchronousExceptionPathAbsent
        [releaseFifo, readerReadyPath]
      createNamedPipe releaseFifo commandActivityLeaseMode
      finallyPreservingPrimary
        (restore action)
        ( runCleanupsPreservingFailures
            [ ignoreIOException (removeFile readerReadyPath),
              ignoreIOException (removeFile releaseFifo),
              synchroniseDirectory (takeDirectory releaseFifo)
            ]
        )

requireSynchronousExceptionPathAbsent :: FilePath -> IO ()
requireSynchronousExceptionPathAbsent path = do
  existingStatus <-
    try @IOException (getSymbolicLinkStatus path)
  case existingStatus of
    Left failure
      | isDoesNotExistError failure -> pure ()
      | otherwise -> ioError failure
    Right _ ->
      ioError
        ( userError
            ( "bounded-command synchronous-exception path already exists: "
                <> path
            )
        )

runSynchronousProtocolExceptionHook ::
  Word64 ->
  SupervisedSession ->
  CommandIdentity ->
  IO ()
runSynchronousProtocolExceptionHook deadline session identity =
  case synchronousExceptionPaths identity of
    Nothing -> pure ()
    Just (identityPath, releaseFifo) -> do
      release <-
        runActionBeforeDeadline
          deadline
          ( readNamedPipePayloadAfterReady
              (synchronousExceptionReaderReadyPath releaseFifo)
              releaseFifo
          )
      unless (release == "release\n") $
        ioError
          ( userError
              ( "bounded-command synchronous-exception release was invalid: "
                  <> show release
              )
          )
      encodedEvidence <-
        runActionBeforeDeadline deadline (ByteString.readFile identityPath)
      evidence <-
        either
          ( \failure ->
              ioError
                ( userError
                    ( "bounded-command synchronous-exception identity was invalid: "
                        <> failure
                    )
                )
          )
          pure
          (Aeson.eitherDecodeStrict' encodedEvidence)
      pinIdentity <-
        requireSessionIdentity
          "synchronous-exception target-group leader"
          (supervisedTargetGroupLeaderIdentity session)
      validateSynchronousExceptionTree pinIdentity evidence
      throwIO SynchronousProtocolTestFailure

publishSynchronousExceptionReaderReady :: FilePath -> IO ()
publishSynchronousExceptionReaderReady readyPath = mask $ \restore -> do
  descriptor <-
    restore
      ( openFd
          readyPath
          WriteOnly
          defaultFileFlags
            { exclusive = True,
              nofollow = True,
              creat = Just commandActivityLeaseMode,
              cloexec = True
            }
      )
  finallyPreservingPrimary
    ( restore $ do
        writeFdFullyBlocking descriptor "reader-ready\n"
        fileSynchronise descriptor
    )
    (ignoreIOException (closeFd descriptor))
  synchroniseDirectory (takeDirectory readyPath)

readNamedPipePayloadAfterReady ::
  FilePath ->
  FilePath ->
  IO ByteString.ByteString
readNamedPipePayloadAfterReady readyPath fifoPath = mask $ \restore -> do
  descriptor <-
    restore
      ( openFd
          fifoPath
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              nonBlock = True,
              cloexec = True
            }
      )
  finallyPreservingPrimary
    ( do
        publishSynchronousExceptionReaderReady readyPath
        restore (readPayload descriptor 0 [] False)
    )
    (ignoreIOException (closeFd descriptor))
  where
    maximumBytes = 64

    readPayload descriptor bytesRead chunks receivedAny = do
      result <-
        try @IOException
          ( PosixByteString.fdRead
              descriptor
              (fromIntegral (maximumBytes + 1 - bytesRead))
          )
      case result of
        Left failure
          | retryableDescriptorError failure ->
              yield >> readPayload descriptor bytesRead chunks receivedAny
          | ioeGetErrorType failure == EOF ->
              handleEmpty descriptor bytesRead chunks receivedAny
          | otherwise -> ioError failure
        Right contents
          | ByteString.null contents ->
              handleEmpty descriptor bytesRead chunks receivedAny
          | ByteString.length contents > maximumBytes - bytesRead ->
              ioError
                ( userError
                    "bounded-command synchronous-exception release exceeds its size limit"
                )
          | otherwise ->
              readPayload
                descriptor
                (bytesRead + ByteString.length contents)
                (contents : chunks)
                True

    handleEmpty descriptor bytesRead chunks receivedAny
      | receivedAny = pure (ByteString.concat (reverse chunks))
      | otherwise =
          yield >> readPayload descriptor bytesRead chunks False

runSupervisorProtocol ::
  BoundedCommand command ->
  SupervisedSession ->
  Word64 ->
  IO ProtocolReport
runSupervisorProtocol command session deadline =
  withSynchronousExceptionFifo
    (boundedCommandIdentity command)
    (runSupervisorProtocolSession command session deadline)

runSupervisorProtocolSession ::
  BoundedCommand command ->
  SupervisedSession ->
  Word64 ->
  IO ProtocolReport
runSupervisorProtocolSession command session deadline = do
  let rendered = boundedRenderedCommand command
      plan =
        SupervisorPlan
          { supervisorPlanAnchorIdentity =
              trackedHelperIdentity (supervisedAnchor session),
            supervisorPlanHelperEnvironment =
              renderSubprocessEnv (boundedEnvironment command),
            supervisorPlanExecutable = renderedExecutable rendered,
            supervisorPlanExecutableSnapshot =
              renderedExecutableIdentity rendered,
            supervisorPlanRetainedExecutableExpectation =
              boundedRetainedExecutableExpectation command,
            supervisorPlanExecutableSnapshotRoot =
              subprocessEnvRuntimeRoot (boundedEnvironment command)
                </> "command-executable-snapshots",
            supervisorPlanArguments = renderedArguments rendered,
            supervisorPlanInput =
              TextEncoding.encodeUtf8 (Text.pack (renderedInput rendered)),
            supervisorPlanEnvironment =
              renderSubprocessEnv (boundedEnvironment command)
                <> renderedEnvironment rendered,
            supervisorPlanWorkingDirectory = renderedWorkingDirectory rendered,
            supervisorPlanProvisioningMutationWorkingDirectory =
              provisioningMutationWorkingDirectoryWire
                <$> boundedProvisioningMutationWorkingDirectory command,
            supervisorPlanArtifactLeaseExpectation =
              boundedArtifactLeaseExpectation command,
            supervisorPlanArtifactGenerationLeaseExpectation =
              boundedArtifactGenerationLeaseExpectation command,
            supervisorPlanInstalledPythonSourceIsolationExpectation =
              boundedInstalledPythonSourceIsolationExpectation command,
            supervisorPlanForceControlFailure =
              supervisorControlFailureRequested (boundedCommandIdentity command),
            supervisorPlanForceTargetSetupFailure =
              targetSetupFailureRequested (boundedCommandIdentity command),
            supervisorPlanAnchorPrePublicationDeathPath =
              anchorPrePublicationDeathReadyPath
                (boundedCommandIdentity command),
            supervisorPlanPrePreparedStopPath =
              supervisorPrePreparedStopPath (boundedCommandIdentity command),
            supervisorPlanCustodyHandoffStopPath =
              supervisorCustodyHandoffStopPath (boundedCommandIdentity command),
            supervisorPlanSynchronousExceptionIdentityPath =
              fst <$> synchronousExceptionPaths (boundedCommandIdentity command),
            supervisorPlanProtocolIsolationReadyPath =
              supervisorProtocolIsolationReadyPath (boundedCommandIdentity command),
            supervisorPlanReapEvidencePrefix =
              designatedOwnerReapEvidencePrefix (boundedCommandIdentity command),
            supervisorPlanTerminalObservationPath =
              supervisorTerminalObservationPath (boundedCommandIdentity command),
            supervisorPlanProtocolEvidenceCase =
              protocolEvidenceTestCase (boundedCommandIdentity command)
          }
      observeSupervisorCustody = do
        anchorEvent <-
          readJsonFrameBefore
            deadline
            "anchor event"
            (supervisedAnchorOutput session)
        case anchorEvent of
          AnchorSupervisorBorn provisionalSupervisor -> do
            let anchorIdentity =
                  trackedHelperIdentity (supervisedAnchor session)
            evidence <-
              Protocol.observeSupervisorCustodyEvidence
                (activityProcessId anchorIdentity)
                (activityProcessGroup anchorIdentity)
                (activityProcessBirthIdentity anchorIdentity)
                (provisionalProcessId provisionalSupervisor)
                (provisionalProcessGroup provisionalSupervisor)
                (provisionalBirthIdentity provisionalSupervisor)
            modifyMVar_
              (supervisedSupervisorProvisional session)
              (const (pure (Just provisionalSupervisor)))
            pure evidence
          AnchorKernelFailure failure ->
            ioError (userError failure)
          _ ->
            ioError
              (userError "bounded-command anchor skipped supervisor custody")
      observePinCustody = do
        anchorEvent <-
          readJsonFrameBefore
            deadline
            "anchor event"
            (supervisedAnchorOutput session)
        case anchorEvent of
          AnchorPinBorn provisionalPin -> do
            provisionalSupervisor <-
              requireProvisionalSessionIdentity
                "provisional supervisor"
                (supervisedSupervisorProvisional session)
            let anchorIdentity =
                  trackedHelperIdentity (supervisedAnchor session)
            evidence <-
              Protocol.observePinCustodyEvidence
                (activityProcessId anchorIdentity)
                (activityProcessGroup anchorIdentity)
                (activityProcessBirthIdentity anchorIdentity)
                (provisionalProcessId provisionalSupervisor)
                (provisionalProcessGroup provisionalSupervisor)
                (provisionalBirthIdentity provisionalSupervisor)
                (provisionalProcessId provisionalPin)
                (provisionalProcessGroup provisionalPin)
                (provisionalBirthIdentity provisionalPin)
            modifyMVar_
              (supervisedPinProvisional session)
              (const (pure (Just provisionalPin)))
            pure evidence
          AnchorKernelFailure failure ->
            ioError (userError failure)
          _ ->
            ioError (userError "bounded-command anchor skipped pin custody")
      awaitReady = do
        anchorEvent <-
          readJsonFrameBefore
            deadline
            "anchor event"
            (supervisedAnchorOutput session)
        case anchorEvent of
          AnchorSupervisorReady
            supervisorIdentity
            targetGroupLeaderIdentity -> do
              provisionalSupervisor <-
                requireProvisionalSessionIdentity
                  "provisional supervisor"
                  (supervisedSupervisorProvisional session)
              validateCustodyTransition
                "supervisor"
                provisionalSupervisor
                supervisorIdentity
              provisionalPin <-
                requireProvisionalSessionIdentity
                  "provisional target-group pin"
                  (supervisedPinProvisional session)
              validateCustodyTransition
                "target-group pin"
                provisionalPin
                targetGroupLeaderIdentity
              modifyMVar_
                (supervisedSupervisorIdentity session)
                (const (pure (Just supervisorIdentity)))
              modifyMVar_
                (supervisedTargetGroupLeaderIdentity session)
                (const (pure (Just targetGroupLeaderIdentity)))
              runPreLeaseTestHook
                (trackedHelperIdentity (supervisedAnchor session))
                supervisorIdentity
                targetGroupLeaderIdentity
                (boundedCommandIdentity command)
              Protocol.observeSupervisorReadyEvidence
                (activityProcessId supervisorIdentity)
                (activityProcessGroup supervisorIdentity)
                (activityProcessBirthIdentity supervisorIdentity)
                (activityProcessId targetGroupLeaderIdentity)
                (activityProcessGroup targetGroupLeaderIdentity)
                (activityProcessBirthIdentity targetGroupLeaderIdentity)
          AnchorKernelFailure failure ->
            ioError (userError failure)
          _ ->
            ioError
              (userError "bounded-command anchor sent terminal before supervisor-ready")
      planLeasePublication = do
        supervisorIdentity <-
          requireSessionIdentity
            "supervisor"
            (supervisedSupervisorIdentity session)
        targetGroupLeaderIdentity <-
          requireSessionIdentity
            "target-group leader"
            (supervisedTargetGroupLeaderIdentity session)
        ownerProcessId <- fromIntegral <$> getProcessID
        ownerProcessGroup <- fromIntegral <$> getProcessGroupID
        ownerBirthIdentity <-
          readProcessBirthIdentity ownerProcessId
            >>= maybe
              ( ioError
                  ( userError
                      "bounded-command cannot observe its publishing owner birth identity"
                  )
              )
              pure
        let ownerIdentity =
              ActivityProcessIdentity
                { activityProcessId = ownerProcessId,
                  activityProcessGroup = ownerProcessGroup,
                  activityProcessBirthIdentity = ownerBirthIdentity
                }
        let activityDocument =
              CommandActivityLeaseDocument
                { activityOwnerProcessGroup = ownerProcessGroup,
                  activityCommandIdentity =
                    trackedHelperIdentity (supervisedAnchor session),
                  activityIdentities =
                    CommandActivityDurable
                      ownerIdentity
                      supervisorIdentity
                      targetGroupLeaderIdentity
                }
            activeRuntimeRoot =
              subprocessEnvRuntimeRoot (boundedEnvironment command)
        incomingActivityName <-
          either
            (ioError . userError)
            pure
            (incomingCommandActivityFileName activityDocument)
        let plannedActivity =
              plannedCommandActivity
                activeRuntimeRoot
                incomingActivityName
                activityDocument
        modifyMVar_
          (supervisedPublishedActivity session)
          (const (pure (Just plannedActivity)))
        pure
          ( Activity.planActivityPublication
              (commandActivityRoot activeRuntimeRoot)
              (publishedActivityPath plannedActivity)
              incomingActivityName
              (LazyByteString.toStrict (Aeson.encode activityDocument))
              (activityDurabilityMarkers (boundedCommandIdentity command))
              ( incomingActivityPublicationTestHooks
                  (boundedCommandIdentity command)
              )
          )
      finishTarget = do
        runSynchronousProtocolExceptionHook
          deadline
          session
          (boundedCommandIdentity command)
        anchorEvent <-
          readJsonFrameBefore
            deadline
            "anchor event"
            (supervisedAnchorOutput session)
        case anchorEvent of
          AnchorTerminal
            supervisorExit
            terminal
            inputEvidence
            stdoutEvidence
            stderrEvidence ->
              pure
                ( ProtocolTerminal
                    supervisorExit
                    terminal
                    inputEvidence
                    stdoutEvidence
                    stderrEvidence
                )
          AnchorKernelFailure failure ->
            pure (ProtocolKernelFailure failure)
          _ ->
            ioError
              (userError "bounded-command anchor sent a non-terminal custody event")
  Protocol.withCommandSession
    deadline
    (supervisedAnchorControl session)
    plan
    ( \anchorReady ->
        Protocol.awaitSupervisorReady
          observeSupervisorCustody
          observePinCustody
          awaitReady
          anchorReady
          ( \supervisorReady ->
              Protocol.publishLease
                planLeasePublication
                supervisorReady
                ( \leaseDurable ->
                    Protocol.startTarget
                      leaseDurable
                      (Protocol.finishTarget finishTarget)
                )
          )
    )

requireSessionIdentity ::
  String ->
  MVar (Maybe ActivityProcessIdentity) ->
  IO ActivityProcessIdentity
requireSessionIdentity label identityState = do
  maybeIdentity <- readMVar identityState
  maybe
    (ioError (userError ("bounded-command " <> label <> " identity is unavailable")))
    pure
    maybeIdentity

requireProvisionalSessionIdentity ::
  String ->
  MVar (Maybe ProvisionalProcessIdentity) ->
  IO ProvisionalProcessIdentity
requireProvisionalSessionIdentity label identityState = do
  maybeIdentity <- readMVar identityState
  maybe
    (ioError (userError ("bounded-command " <> label <> " identity is unavailable")))
    pure
    maybeIdentity

validateCustodyTransition ::
  String ->
  ProvisionalProcessIdentity ->
  ActivityProcessIdentity ->
  IO ()
validateCustodyTransition label provisional finalIdentity = do
  unless
    ( provisionalProcessId provisional == activityProcessId finalIdentity
        && provisionalBirthIdentity provisional
          == activityProcessBirthIdentity finalIdentity
        && activityProcessId finalIdentity
          == activityProcessGroup finalIdentity
    )
    (ioError (userError ("bounded-command " <> label <> " custody transition is invalid")))
  validateObservedActivityLeader label finalIdentity

validateObservedActivityLeader ::
  String ->
  ActivityProcessIdentity ->
  IO ()
validateObservedActivityLeader label identity = do
  observedBirthIdentityBefore <-
    readProcessBirthIdentity (activityProcessId identity)
  observedProcessGroup <-
    getProcessGroupIDOf (fromIntegral (activityProcessId identity))
  observedBirthIdentityAfter <-
    readProcessBirthIdentity (activityProcessId identity)
  unless
    ( observedBirthIdentityBefore
        == Just (activityProcessBirthIdentity identity)
        && observedBirthIdentityAfter
          == Just (activityProcessBirthIdentity identity)
        && fromIntegral observedProcessGroup == activityProcessGroup identity
        && activityProcessGroup identity == activityProcessId identity
    )
    ( ioError
        ( userError
            ("bounded-command cannot verify reported " <> label <> " identity")
        )
    )

validateSynchronousExceptionTree ::
  ActivityProcessIdentity ->
  SynchronousExceptionTreeEvidence ->
  IO ()
validateSynchronousExceptionTree pinIdentity evidence = do
  let targetIdentity = synchronousTargetIdentity evidence
      descendantIdentity = synchronousDescendantIdentity evidence
      targetProcessId = activityProcessId targetIdentity
      descendantProcessId = activityProcessId descendantIdentity
      expectedGroup = activityProcessGroup pinIdentity
  unless
    ( synchronousGroupLeaderIdentity evidence == pinIdentity
        && targetProcessId /= activityProcessId pinIdentity
        && descendantProcessId /= activityProcessId pinIdentity
        && descendantProcessId /= targetProcessId
    )
    ( ioError
        ( userError
            "bounded-command synchronous-exception tree escaped its retained group"
        )
    )
  validateObservedGroupMember "synchronous target" targetIdentity
  validateObservedGroupMember "synchronous descendant" descendantIdentity
  unless
    ( activityProcessGroup targetIdentity == expectedGroup
        && activityProcessGroup descendantIdentity == expectedGroup
    )
    (ioError (userError "bounded-command synchronous tree group identity changed"))

validateProcessInRegisteredGroup ::
  String ->
  Integer ->
  Integer ->
  ActivityProcessIdentity ->
  IO ()
validateProcessInRegisteredGroup label processId expectedGroup groupLeader = do
  groupLeaderBirthBefore <-
    readProcessBirthIdentity (activityProcessId groupLeader)
  observedGroup <-
    fromIntegral
      <$> getProcessGroupIDOf (fromIntegral processId)
  groupLeaderBirthAfter <-
    readProcessBirthIdentity (activityProcessId groupLeader)
  unless
    ( groupLeaderBirthBefore
        == Just (activityProcessBirthIdentity groupLeader)
        && groupLeaderBirthAfter
          == Just (activityProcessBirthIdentity groupLeader)
        && activityProcessId groupLeader == expectedGroup
        && activityProcessGroup groupLeader == expectedGroup
        && observedGroup == expectedGroup
    )
    ( ioError
        ( userError
            ( "bounded-command cannot verify "
                <> label
                <> " in its exact registered group"
            )
        )
    )

validateObservedGroupMember ::
  String ->
  ActivityProcessIdentity ->
  IO ()
validateObservedGroupMember label identity = do
  observedBirthIdentityBefore <-
    readProcessBirthIdentity (activityProcessId identity)
  observedProcessGroup <-
    getProcessGroupIDOf (fromIntegral (activityProcessId identity))
  observedBirthIdentityAfter <-
    readProcessBirthIdentity (activityProcessId identity)
  unless
    ( observedBirthIdentityBefore
        == Just (activityProcessBirthIdentity identity)
        && observedBirthIdentityAfter
          == Just (activityProcessBirthIdentity identity)
        && fromIntegral observedProcessGroup == activityProcessGroup identity
    )
    ( ioError
        ( userError
            ("bounded-command cannot verify reported " <> label <> " identity")
        )
    )

requireCurrentActivityIdentity :: String -> IO ActivityProcessIdentity
requireCurrentActivityIdentity label = do
  processId <- getProcessID
  processGroup <- getProcessGroupID
  birthIdentity <-
    readProcessBirthIdentity (fromIntegral processId)
      >>= maybe
        ( ioError
            ( userError
                ( "bounded-command cannot observe the current "
                    <> label
                    <> " birth identity"
                )
            )
        )
        pure
  let identity =
        ActivityProcessIdentity
          { activityProcessId = fromIntegral processId,
            activityProcessGroup = fromIntegral processGroup,
            activityProcessBirthIdentity = birthIdentity
          }
  unless
    ( validActivityProcessId (activityProcessId identity)
        && validActivityProcessId (activityProcessGroup identity)
    )
    (ioError (userError ("bounded-command " <> label <> " identity is invalid")))
  pure identity

registerCurrentActivityIdentity :: String -> IO ActivityProcessIdentity
registerCurrentActivityIdentity label = do
  processId <- getProcessID
  processGroup <- getProcessGroupID
  birthIdentity <- registerCurrentProcessIdentity
  let identity =
        ActivityProcessIdentity
          { activityProcessId = fromIntegral processId,
            activityProcessGroup = fromIntegral processGroup,
            activityProcessBirthIdentity = birthIdentity
          }
  unless
    ( validActivityProcessId (activityProcessId identity)
        && validActivityProcessId (activityProcessGroup identity)
    )
    (ioError (userError ("bounded-command " <> label <> " identity is invalid")))
  pure identity

publishCurrentHelperIdentity :: String -> IO ()
publishCurrentHelperIdentity label = do
  identity <- registerCurrentActivityIdentity label
  writeJsonFrameHandle stdout (HelperIdentityReady identity)

newtype ReapedChildEvidence
  = ReapedRegisteredChild ActivityProcessIdentity

recordCurrentOwnerReapEvidence ::
  FilePath ->
  [(String, ReapedChildEvidence, String)] ->
  IO ()
recordCurrentOwnerReapEvidence evidencePath children = do
  ownerIdentity <- requireCurrentActivityIdentity "reap owner"
  recordReapEvidence evidencePath ownerIdentity children

recordSupervisorReapEvidence ::
  FilePath ->
  TrackedProcess ->
  TrackedHelper ->
  ActivityProcessIdentity ->
  IO ()
recordSupervisorReapEvidence evidencePath target pin pinIdentity = do
  targetStatus <- readMVar (trackedProcessStatus target)
  pinStatus <- readMVar (trackedHelperExitCode pin)
  case (targetStatus, pinStatus) of
    (Just reapedTarget, Just reapedPin) ->
      recordCurrentOwnerReapEvidence
        evidencePath
        [ ( "target",
            ReapedRegisteredChild (trackedProcessIdentity target),
            show reapedTarget
          ),
          ("group-pin", ReapedRegisteredChild pinIdentity, show reapedPin)
        ]
    _ ->
      ioError
        (userError "bounded-command reap evidence preceded an owned-child reap")

recordReapEvidence ::
  FilePath ->
  ActivityProcessIdentity ->
  [(String, ReapedChildEvidence, String)] ->
  IO ()
recordReapEvidence evidencePath ownerIdentity children =
  LazyByteString.writeFile
    evidencePath
    ( Aeson.encode
        ( Aeson.object
            [ "version" Aeson..= (2 :: Int),
              "owner" Aeson..= activityIdentityEvidence ownerIdentity,
              "reapedChildren"
                Aeson..= [ Aeson.object
                             ( [ "label" Aeson..= label,
                                 "status" Aeson..= status
                               ]
                                 <> reapedChildIdentityFields identity
                             )
                         | (label, identity, status) <- children
                         ]
            ]
        )
    )

reapedChildIdentityFields :: ReapedChildEvidence -> [Pair]
reapedChildIdentityFields evidence =
  case evidence of
    ReapedRegisteredChild identity ->
      [ "identityKind" Aeson..= ("registered" :: String),
        "identity" Aeson..= activityIdentityEvidence identity
      ]

activityIdentityEvidence :: ActivityProcessIdentity -> Aeson.Value
activityIdentityEvidence identity =
  Aeson.object
    [ "processId" Aeson..= activityProcessId identity,
      "processGroup" Aeson..= activityProcessGroup identity,
      "birthIdentity"
        Aeson..= renderProcessBirthIdentity
          (activityProcessBirthIdentity identity)
    ]

-- | Whether the anchor is expected to retire its own executable-snapshot
-- generation and exit on its own, or must be terminated immediately.
--
-- Only an attempt whose supervisor protocol reached a terminal frame leaves
-- the anchor in a state where it is already unwinding; a protocol failure,
-- an expired attempt deadline, or an asynchronous cancellation leaves it
-- blocked, so those paths must not pay a shutdown grace period.
data AnchorShutdownExpectation
  = ExpectAnchorSelfExit
  | TerminateAnchorNow
  deriving (Eq, Show)

anchorShutdownExpectation ::
  Either IOException ProtocolReport ->
  AnchorShutdownExpectation
anchorShutdownExpectation protocol =
  case protocol of
    Right (ProtocolTerminal {}) -> ExpectAnchorSelfExit
    _ -> TerminateAnchorNow

cleanupSupervisedProcesses ::
  BoundedCommand command ->
  SupervisedSession ->
  AnchorShutdownExpectation ->
  IO (Either String ExitCode)
cleanupSupervisedProcesses command session anchorShutdown = mask_ $ do
  let anchor = supervisedAnchor session
      anchorIdentity = trackedHelperIdentity anchor
      tryKillAnchorGroup =
        try @SomeException
          ( signalOwnedUnreapedHelperGroupWith
              sigKILL
              anchor
              anchorIdentity
          )
      tryCloseAnchorControl =
        try @SomeException
          ( ignoreIOException
              (Protocol.closeAnchorControl (supervisedAnchorControl session))
          )
  supervisorProvisionalResult <-
    try @SomeException
      (readMVar (supervisedSupervisorProvisional session))
  supervisorIdentityResult <-
    try @SomeException
      (readMVar (supervisedSupervisorIdentity session))
  pinProvisionalResult <-
    try @SomeException
      (readMVar (supervisedPinProvisional session))
  targetGroupLeaderIdentityResult <-
    try @SomeException
      (readMVar (supervisedTargetGroupLeaderIdentity session))
  initialCleanupResults <-
    mapM
      (try @SomeException)
      ( [ ignoreIOException
            ( signalOwnedUnreapedHelperGroupWith
                sigCONT
                anchor
                anchorIdentity
            )
        ]
          <> preferredIdentityActions
            supervisorIdentityResult
            supervisorProvisionalResult
            ( deferSignalFailureUntilAbsence
                . signalActivityProcessGroupWith sigCONT
            )
            ( deferSignalFailureUntilAbsence
                . signalProvisionalProcessWith sigCONT
            )
          <> preferredIdentityActions
            targetGroupLeaderIdentityResult
            pinProvisionalResult
            ( deferSignalFailureUntilAbsence
                . signalActivityProcessGroupWith sigCONT
            )
            ( deferSignalFailureUntilAbsence
                . signalProvisionalProcessWith sigCONT
            )
      )
  -- The anchor owns retirement of its own exact executable-snapshot
  -- generation. An anchor that reached a terminal frame is already unwinding,
  -- so closing its control channel is its shutdown signal and it is then given
  -- the same bounded window the designated reap uses to finish and exit on its
  -- own; force-terminating it there destroys that retirement and reports a
  -- signalled exit that disagrees with the target's terminal evidence.
  -- Every other path leaves the anchor blocked, so it keeps the prompt
  -- kill-then-close teardown and pays no shutdown grace period.
  (anchorKillAttempt, anchorControlClose, gracefulAnchorExit) <-
    case anchorShutdown of
      TerminateAnchorNow -> do
        killAttempt <- tryKillAnchorGroup
        controlClose <- tryCloseAnchorControl
        pure (killAttempt, controlClose, Right Nothing)
      ExpectAnchorSelfExit -> do
        controlClose <- tryCloseAnchorControl
        graceful <-
          try @SomeException (waitForTrackedHelperMaybe anchor)
        killAttempt <-
          case graceful of
            Right (Just _) -> pure (Right ())
            _ -> tryKillAnchorGroup
        pure (killAttempt, controlClose, graceful)
  anchorProtocolClose <-
    try @SomeException
      (awaitHelperProtocolClose (supervisedAnchorOutput session))
  forcedCleanupResults <-
    mapM
      (try @SomeException)
      ( preferredIdentityActions
          targetGroupLeaderIdentityResult
          pinProvisionalResult
          (deferSignalFailureUntilAbsence . signalActivityProcessGroup)
          ( deferSignalFailureUntilAbsence
              . signalProvisionalProcessWith sigKILL
          )
          <> preferredIdentityActions
            supervisorIdentityResult
            supervisorProvisionalResult
            (deferSignalFailureUntilAbsence . signalActivityProcessGroup)
            ( deferSignalFailureUntilAbsence
                . signalProvisionalProcessWith sigKILL
            )
      )
  anchorReap <-
    try @SomeException (waitForTrackedHelperBounded anchor)
  parentReapEvidence <-
    case (designatedOwnerReapEvidencePrefix (boundedCommandIdentity command), anchorReap) of
      (Just evidencePrefix, Right exitCode) ->
        try @SomeException
          ( recordCurrentOwnerReapEvidence
              (evidencePrefix <> ".parent.json")
              [ ( "anchor",
                  ReapedRegisteredChild anchorIdentity,
                  show exitCode
                )
              ]
          )
      _ -> pure (Right ())
  commandAbsence <-
    try @SomeException
      (awaitRecordedProcessGroupAbsent "anchor" anchorIdentity 500)
  supervisorAbsence <-
    provePreferredIdentityAbsent
      "supervisor"
      supervisorIdentityResult
      supervisorProvisionalResult
  targetAbsence <-
    provePreferredIdentityAbsent
      "target group"
      targetGroupLeaderIdentityResult
      pinProvisionalResult
  snapshotRecovery <-
    case ( renderedExecutableIdentity (boundedRenderedCommand command),
           commandAbsence
         ) of
      (Just _, Right ()) ->
        try @SomeException
          ( recoverDeadExecutableSnapshots
              ( subprocessEnvRuntimeRoot (boundedEnvironment command)
                  </> "command-executable-snapshots"
              )
          )
      _ -> pure (Right ())
  publishedResult <-
    try @SomeException (readMVar (supervisedPublishedActivity session))
  retirementProofHook <-
    case ( publishedResult,
           anchorReap,
           commandAbsence,
           supervisorAbsence,
           targetAbsence,
           snapshotRecovery
         ) of
      (Right (Just _), Right _, Right (), Right (), Right (), Right ()) ->
        try @SomeException
          (runActivityRetirementTestHook (boundedCommandIdentity command))
      _ -> pure (Right ())
  retirement <-
    case ( publishedResult,
           anchorReap,
           commandAbsence,
           supervisorAbsence,
           targetAbsence,
           snapshotRecovery,
           retirementProofHook
         ) of
      (Right (Just activity), Right _, Right (), Right (), Right (), Right (), Right ()) ->
        try @SomeException (retirePublishedCommandActivity activity)
      _ -> pure (Right ())
  closeResults <-
    mapM
      (try @SomeException)
      [ ignoreIOException (hClose (supervisedAnchorOutput session))
      ]
  -- EPERM is not absence evidence. Discharge it only after the designated
  -- reap and exact group-absence proof have both completed.
  let verifiedAnchorKill =
        case (anchorKillAttempt, anchorReap, commandAbsence) of
          (Left failure, Right _, Right ())
            | maybe
                False
                isPermissionError
                (fromException failure :: Maybe IOException) ->
                Right ()
          _ -> anchorKillAttempt
      results =
        initialCleanupResults
          <> [ verifiedAnchorKill,
               anchorControlClose,
               voidResult gracefulAnchorExit
             ]
          <> forcedCleanupResults
          <> [ anchorProtocolClose,
               voidResult anchorReap,
               parentReapEvidence,
               commandAbsence,
               supervisorAbsence,
               targetAbsence,
               snapshotRecovery,
               voidResult supervisorProvisionalResult,
               voidResult supervisorIdentityResult,
               voidResult pinProvisionalResult,
               voidResult targetGroupLeaderIdentityResult,
               voidResult publishedResult,
               retirementProofHook,
               retirement
             ]
          <> closeResults
      asynchronousFailures =
        concatMap
          (filter isAsynchronousException . exceptionFailures)
          results
      failures =
        [ label <> ": " <> displayException failure
        | (label, Left failure) <-
            zip
              (map (("cleanup step " <>) . show) [(1 :: Int) ..])
              results
        ]
      outcome =
        case (failures, anchorReap) of
          ([], Right exitCode) -> Right exitCode
          ([], Left failure) ->
            Left
              ("runBoundedCommand: anchor reap failed: " <> displayException failure)
          (_ : _, _) ->
            Left
              ( "runBoundedCommand: cleanup failed: "
                  <> List.intercalate "; " failures
              )
  case asynchronousFailures of
    [] -> pure outcome
    _ -> do
      runCleanupsPreservingFailures
        ( map throwIO asynchronousFailures
            <> either
              (\failure -> [ioError (userError failure)])
              (const [])
              outcome
        )
      ioError
        (userError "runBoundedCommand: asynchronous cleanup failure escaped aggregation")

-- ESRCH and EPERM are not treated as proof here. Cleanup defers them and
-- succeeds only if the later exact process-group proof reaches ESRCH before
-- its bounded deadline.
deferSignalFailureUntilAbsence :: IO () -> IO ()
deferSignalFailureUntilAbsence action = do
  result <- try @IOException action
  case result of
    Right () -> pure ()
    Left failure
      | isDoesNotExistError failure || isPermissionError failure -> pure ()
      | otherwise -> ioError failure

preferredIdentityActions ::
  Either SomeException (Maybe ActivityProcessIdentity) ->
  Either SomeException (Maybe ProvisionalProcessIdentity) ->
  (ActivityProcessIdentity -> IO ()) ->
  (ProvisionalProcessIdentity -> IO ()) ->
  [IO ()]
preferredIdentityActions finalResult provisionalResult finalAction provisionalAction =
  case finalResult of
    Right (Just identity) -> [finalAction identity]
    _ ->
      case provisionalResult of
        Right (Just identity) -> [provisionalAction identity]
        _ -> []

provePreferredIdentityAbsent ::
  String ->
  Either SomeException (Maybe ActivityProcessIdentity) ->
  Either SomeException (Maybe ProvisionalProcessIdentity) ->
  IO (Either SomeException ())
provePreferredIdentityAbsent label finalResult provisionalResult =
  case finalResult of
    Left failure -> pure (Left failure)
    Right (Just identity) ->
      try @SomeException (awaitRecordedProcessGroupAbsent label identity 500)
    Right Nothing ->
      case provisionalResult of
        Left failure -> pure (Left failure)
        Right Nothing -> pure (Right ())
        Right (Just identity) ->
          try @SomeException (awaitProvisionalProcessQuiescent label identity)

voidResult ::
  Either SomeException value ->
  Either SomeException ()
voidResult =
  void

awaitHelperProtocolClose :: Handle -> IO ()
awaitHelperProtocolClose handle = do
  _ <-
    timeout
      helperShutdownGraceMicros
      (readHandleToEnd maximumSupervisorFrameBytes handle)
  pure ()

helperShutdownGraceMicros :: Int
helperShutdownGraceMicros = 1000000

takeMVarBounded ::
  String ->
  MVar value ->
  IO (Either String value)
takeMVarBounded label value = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.pollLimitedDeadline 10000 2 2 201)
      pollValue
  pure
    ( Readiness.foldReadiness
        Right
        (const timedOut)
        (const timedOut)
        outcome
    )
  where
    pollValue = do
      result <- tryTakeMVar value
      pure
        ( maybe
            (Left (Readiness.Progress 0 1 (Text.pack ("waiting for " <> label))))
            Right
            result
        )
    timedOut =
      Left ("runBoundedCommand: timed out waiting for " <> label)

finalizeSupervisedAttempt ::
  CommandIdentity ->
  FilePath ->
  Either IOException ProtocolReport ->
  Either String ExitCode ->
  Either String (Either SomeException ByteString.ByteString) ->
  AttemptOutcome
finalizeSupervisedAttempt
  commandIdentity
  executableSnapshotRoot
  protocol
  cleanup
  diagnostic =
    case cleanup of
      Left cleanupFailure ->
        AttemptKernelFailure
          (protocolEvidence protocol <> "\ncleanup also failed:\n" <> cleanupFailure)
      Right anchorExit ->
        case protocol of
          Left failure
            | "attempt deadline expired" `List.isInfixOf` displayException failure ->
                AttemptTimedOut
            | otherwise ->
                AttemptKernelFailure
                  ( "runBoundedCommand: protocol failed: "
                      <> displayException failure
                      <> helperDiagnosticEvidence diagnostic
                  )
          Right (ProtocolKernelFailure failure) ->
            AttemptKernelFailure
              ( failure
                  <> "; anchor exit "
                  <> show anchorExit
                  <> helperDiagnosticEvidence diagnostic
              )
          Right
            ( ProtocolTerminal
                supervisorExit
                terminal
                inputEvidence
                stdoutEvidence
                stderrEvidence
              ) ->
              finalizeTerminalEvidence
                commandIdentity
                executableSnapshotRoot
                anchorExit
                supervisorExit
                terminal
                inputEvidence
                stdoutEvidence
                stderrEvidence
                diagnostic

protocolEvidence :: Either IOException ProtocolReport -> String
protocolEvidence protocol =
  case protocol of
    Left failure ->
      "runBoundedCommand: protocol failure " <> displayException failure
    Right report ->
      "runBoundedCommand: provisional protocol report " <> show report

helperDiagnosticEvidence ::
  Either String (Either SomeException ByteString.ByteString) ->
  String
helperDiagnosticEvidence diagnostic =
  case diagnostic of
    Left failure -> "; anchor stderr unavailable: " <> failure
    Right (Left failure) ->
      "; anchor stderr capture failed: " <> displayException failure
    Right (Right contents)
      | ByteString.null contents -> ""
      | otherwise -> "; anchor stderr: " <> ByteString8.unpack contents

finalizeTerminalEvidence ::
  CommandIdentity ->
  FilePath ->
  ExitCode ->
  ExitCode ->
  TargetTerminal ->
  InputEvidence ->
  CaptureEvidence ->
  CaptureEvidence ->
  Either String (Either SomeException ByteString.ByteString) ->
  AttemptOutcome
finalizeTerminalEvidence
  commandIdentity
  executableSnapshotRoot
  anchorExit
  supervisorExit
  terminal
  inputEvidence
  stdoutEvidence
  stderrEvidence
  diagnostic
    | anchorExit /= ExitSuccess =
        kernelFailure
          ( "anchor terminal disagreed with anchor exit "
              <> show anchorExit
          )
    | not (supervisorExitMatchesTerminal supervisorExit terminal) =
        kernelFailure
          ( "supervisor terminal status did not match target provenance: "
              <> show supervisorExit
              <> "; target terminal "
              <> show terminal
          )
    | InputFailed failure <- inputEvidence =
        kernelFailure ("stdin writer failed: " <> failure)
    | CaptureFailed failure <- stdoutEvidence =
        kernelFailure ("stdout capture failed: " <> failure <> peerEvidence stderrEvidence)
    | CaptureFailed failure <- stderrEvidence =
        kernelFailure ("stderr capture failed: " <> failure <> peerEvidence stdoutEvidence)
    | CaptureCompleted stdoutBytes <- stdoutEvidence,
      CaptureCompleted stderrBytes <- stderrEvidence =
        case ( strictUtf8 "stdout" stdoutBytes,
               strictUtf8 "stderr" stderrBytes
             ) of
          (Left failure, _) -> kernelFailure failure
          (_, Left failure) -> kernelFailure failure
          (Right out, Right err) ->
            case terminal of
              TargetKernelFailure failure ->
                AttemptKernelFailure
                  (failure <> capturedCommandOutput out err)
              _ ->
                AttemptCompleted
                  ( classifyTargetTerminal
                      commandIdentity
                      executableSnapshotRoot
                      terminal
                      out
                      err
                  )
                  terminal
                  stdoutBytes
                  stderrBytes
    where
      kernelFailure failure =
        AttemptKernelFailure
          ( failure
              <> "; input "
              <> show inputEvidence
              <> "; stdout "
              <> show stdoutEvidence
              <> "; stderr "
              <> show stderrEvidence
              <> helperDiagnosticEvidence diagnostic
          )
      peerEvidence evidence =
        case evidence of
          CaptureCompleted contents ->
            case TextEncoding.decodeUtf8' contents of
              Left _ -> "; peer capture is not valid UTF-8"
              Right text -> "; peer capture: " <> Text.unpack text
          CaptureFailed failure -> "; peer capture failed: " <> failure

supervisorExitMatchesTerminal ::
  ExitCode ->
  TargetTerminal ->
  Bool
supervisorExitMatchesTerminal supervisorExit terminal =
  case terminal of
    TargetKernelFailure _ -> supervisorExit == ExitFailure 125
    _ -> supervisorExit == ExitSuccess

strictUtf8 :: String -> ByteString.ByteString -> Either String String
strictUtf8 label contents =
  case TextEncoding.decodeUtf8' contents of
    Left failure ->
      Left
        ( "runBoundedCommand: "
            <> label
            <> " was not valid UTF-8: "
            <> show failure
        )
    Right decoded -> Right (Text.unpack decoded)

classifyTargetTerminal ::
  CommandIdentity ->
  FilePath ->
  TargetTerminal ->
  String ->
  String ->
  CommandOutcome
classifyTargetTerminal commandIdentity executableSnapshotRoot terminal out err =
  case terminal of
    TargetExited 0 ->
      case validateInstalledRunnerLoaderEvidence
        commandIdentity
        executableSnapshotRoot
        out
        err of
        Left failure -> CommandFailedKernel failure
        Right validatedOutput -> CommandSucceeded validatedOutput
    TargetExited exitCode ->
      classifyExit (ExitFailure exitCode) out err
    TargetSignaled signal coreDumped ->
      CommandFailedFatal
        ( "terminated by signal "
            <> show signal
            <> (if coreDumped then " (core dumped)" else "")
            <> capturedCommandOutput out err
        )
    TargetKernelFailure failure ->
      CommandFailedKernel (failure <> capturedCommandOutput out err)

validateInstalledRunnerLoaderEvidence ::
  CommandIdentity ->
  FilePath ->
  String ->
  String ->
  Either String String
validateInstalledRunnerLoaderEvidence
  commandIdentity
  executableSnapshotRoot
  out
  err =
    case commandIdentity of
      ProvisioningCommandIdentity
        (Provisioning.InstalledRunnerSmokeOperation _) -> do
          audited <- mapM parseDyldAuditLine (lines err)
          let loadedPaths =
                [ path
                | DyldLoadedPath path <- audited
                ]
              applicationError =
                unlines
                  [ line
                  | (line, NotDyldAuditLine) <- zip (lines err) audited
                  ]
          when
            (null loadedPaths)
            (Left "installed runner emitted no DYLD loader provenance")
          ownedRoots <-
            mapM
              (classifyLoadedLibrary executableSnapshotRoot)
              loadedPaths
          let artifactRoots = List.nub (catMaybes ownedRoots)
          unless
            (length artifactRoots == 1)
            ( Left
                "installed runner loader provenance did not name exactly one sealed artifact generation"
            )
          let validatedOutput =
                trimCapturedOutput
                  (if null (trimCapturedOutput out) then applicationError else out)
          when
            (null validatedOutput)
            (Left "installed runner smoke returned no validated version output")
          Right validatedOutput
      _ -> Right out

-- | Validate a retained generation's loader provenance and return the runner's
-- own diagnostics — the stderr lines that are not @dyld@ frames at all.
--
-- A runner that writes its version banner to stderr (as @llama-cli --version@
-- does) leaves an empty stdout, so the caller needs those lines to read the
-- exact runtime version. Loader frames, including the delayed-initialization
-- scheduling frames, are excluded: they are loader output, not the runner's.
-- | Audit one sealed run against the loader that actually performed its loads.
auditSealedRun ::
  SealedRunLoaderAudit ->
  [FilePath] ->
  ByteString.ByteString ->
  Either Text.Text ByteString.ByteString
auditSealedRun audit =
  case audit of
    DyldSealedRunAudit -> validateRetainedArtifactLoaderEvidence
    ElfSealedRunAudit -> validateRetainedElfArtifactLoaderEvidence

validateRetainedArtifactLoaderEvidence ::
  [FilePath] ->
  ByteString.ByteString ->
  Either Text.Text ByteString.ByteString
validateRetainedArtifactLoaderEvidence ownedRoots stderrBytes = do
  stderrText <-
    either
      ( Left
          . ("installed runner stderr is not valid UTF-8: " <>)
          . Text.pack
          . show
      )
      Right
      (TextEncoding.decodeUtf8' stderrBytes)
  audited <-
    either
      (Left . Text.pack)
      Right
      (mapM parseDyldAuditLine (Text.unpack <$> Text.lines stderrText))
  classifySealedRunLoads
    "DYLD"
    systemDyldLibraryPath
    ownedRoots
    [loadedPath | DyldLoadedPath loadedPath <- audited]
  pure
    ( TextEncoding.encodeUtf8
        ( Text.unlines
            [ line
            | (line, NotDyldAuditLine) <- zip (Text.lines stderrText) audited
            ]
        )
    )

-- | The Linux counterpart of the @dyld@ audit.
--
-- Without this, a resolver that disagreed with the real loader would bind the
-- wrong object and the smoke would not notice, so the Linux loader evidence
-- would be a faithful /derivation/ rather than an /observation/. The
-- @ld.so@ analogue of @DYLD_PRINT_LIBRARIES@ is @LD_DEBUG=libs@, which reports
-- the objects @dlopen@ pulls in as well as the linked ones — the same class of
-- defect the Apple lane found in the Python home's @lib-dynload@.
validateRetainedElfArtifactLoaderEvidence ::
  [FilePath] ->
  ByteString.ByteString ->
  Either Text.Text ByteString.ByteString
validateRetainedElfArtifactLoaderEvidence ownedRoots stderrBytes = do
  stderrText <-
    either
      ( Left
          . ("sealed Linux runner stderr is not valid UTF-8: " <>)
          . Text.pack
          . show
      )
      Right
      (TextEncoding.decodeUtf8' stderrBytes)
  audited <-
    either
      (Left . Text.pack)
      Right
      (mapM parseElfAuditLine (Text.unpack <$> Text.lines stderrText))
  classifySealedRunLoads
    "LD_DEBUG"
    systemElfLibraryPath
    ownedRoots
    [loadedPath | ElfLoadedPath loadedPath <- audited]
  pure
    ( TextEncoding.encodeUtf8
        ( Text.unlines
            [ line
            | (line, NotElfAuditLine) <- zip (Text.lines stderrText) audited
            ]
        )
    )

-- | The three aggregate checks that make a loader audit meaningful, shared by
-- both loaders: something was loaded, at least one object came from the sealed
-- generation, and nothing outside the generation and the operating system was
-- loaded.
--
-- Per-frame strictness is not what provides the guarantee — these are. A future
-- loader that changed its load-record format fails loudly here rather than
-- passing silently.
classifySealedRunLoads ::
  Text.Text ->
  (FilePath -> Bool) ->
  [FilePath] ->
  [FilePath] ->
  Either Text.Text ()
classifySealedRunLoads loaderName systemLibraryPath ownedRoots loadedPaths = do
  when
    (null loadedPaths)
    ( Left
        ( "sealed runner emitted no "
            <> loaderName
            <> " loader provenance"
        )
    )
  unless
    (null unsealedLoads)
    ( Left
        ( "sealed runner loaded an unsealed non-system library: "
            <> Text.pack (List.intercalate ", " unsealedLoads)
        )
    )
  when
    (null artifactOwnedLoads)
    (Left "sealed runner loaded no library from its exact artifact generation")
  where
    -- An installed artifact owns exactly one root. An image target owns the
    -- closure roots its catalog entry declares, because the payload it execs
    -- lives in the immutable image rather than in the generation.
    ownedLoad loadedPath =
      any (`pathWithinOwnedRoot` loadedPath) ownedRoots
    artifactOwnedLoads =
      [ loadedPath
      | loadedPath <- loadedPaths,
        ownedLoad loadedPath
      ]
    unsealedLoads =
      [ loadedPath
      | loadedPath <- loadedPaths,
        not (systemLibraryPath loadedPath || ownedLoad loadedPath)
      ]

data ElfAuditLine
  = NotElfAuditLine
  | -- | An @ld.so@ frame that carries no loaded path: a search step, a cache
    -- probe, a candidate that was tried, or the program-entry and
    -- control-transfer frames, whose operand is @argv[0]@ rather than a
    -- resolved path.
    ElfLoaderFrame
  | ElfLoadedPath !FilePath
  deriving (Eq, Show)

-- | Only a frame that announces itself as a load record is provenance.
--
-- Measured against glibc 2.39 @LD_DEBUG=libs@, whose frames are all
-- @\<pid\>:\\t\<payload\>@:
--
-- > find library=libc.so.6 [0]; searching
-- >  search cache=/etc/ld.so.cache
-- >   trying file=/lib/aarch64-linux-gnu/libc.so.6
-- > calling init: /lib/aarch64-linux-gnu/libc.so.6
-- > initialize program: python3
-- > transferring control: python3
--
-- @calling init:@ names a shared object the loader actually mapped and
-- initialized. @initialize program:@ also names a mapped object when its
-- operand is absolute; glibc preserves the absolute @argv[0]@ used by the
-- closed image-target smoke, and that observation is required for a valid
-- fully static target that loads no artifact-owned shared object. A bare
-- @python3@ remains commentary. @trying file=@ names candidates the loader may
-- reject, so admitting it would launder paths that were never loaded.
--
-- This is the same inversion the @dyld@ parser settled on: an unrecognised
-- frame is loader commentary carrying no path, and the guarantee comes from the
-- aggregate checks in 'classifySealedRunLoads'.
parseElfAuditLine :: String -> Either String ElfAuditLine
parseElfAuditLine rawLine =
  case elfLinePayload rawLine of
    Nothing -> Right NotElfAuditLine
    Just payload ->
      case List.stripPrefix "calling init:" payload of
        Nothing ->
          case List.stripPrefix "initialize program:" payload of
            Nothing -> Right ElfLoaderFrame
            Just loadedPath
              | isAbsolute (dropWhile isSpace loadedPath) ->
                  validateElfLoadedPath (dropWhile isSpace loadedPath)
              | otherwise -> Right ElfLoaderFrame
        Just loadedPath ->
          validateElfLoadedPath (dropWhile isSpace loadedPath)

-- | An @ld.so@ debug frame is @\<spaces\>\<pid\>:\<tab\>\<payload\>@. Anything
-- else on the captured stream is the runner's own output.
elfLinePayload :: String -> Maybe String
elfLinePayload rawLine =
  case break (== ':') (dropWhile isSpace rawLine) of
    (processId, ':' : '\t' : payload)
      | not (null processId),
        all isDigit processId ->
          Just (dropWhile isSpace payload)
    _ -> Nothing

-- | A loaded object must be an absolute, NUL-free path that stays absolute once
-- its @..@ components are collapsed.
--
-- glibc reports the path it opened, which legitimately carries @..@ when the
-- search entry did: a stock CPython reports
-- @\/usr\/local\/bin\/..\/lib\/libpython3.12.so.1.0@. Banning @..@ outright
-- would therefore reject a correct load record, which is the same mistake the
-- delocated-wheel install-name ban made. Collapsing is also the /safe/
-- operation for the containment test that follows: an ascending path collapses
-- to where it actually resolves, so it is classified as unsealed rather than
-- laundered into the artifact root.
validateElfLoadedPath :: String -> Either String ElfAuditLine
validateElfLoadedPath loadedPath
  | null loadedPath || not (isAbsolute loadedPath) = malformed
  | '\NUL' `elem` loadedPath =
      Left "sealed Linux runner LD_DEBUG loader provenance contains NUL"
  | otherwise =
      case collapseElfLoadedPath loadedPath of
        Nothing -> malformed
        Just collapsed -> Right (ElfLoadedPath collapsed)
  where
    malformed =
      Left
        ( "sealed Linux runner emitted malformed LD_DEBUG loader provenance: "
            <> show (take 200 loadedPath)
        )

collapseElfLoadedPath :: FilePath -> Maybe FilePath
collapseElfLoadedPath loadedPath =
  fmap (("/" </>) . joinPath . reverse) (foldl descend (Just []) components)
  where
    components =
      filter
        (\component -> component /= "/" && component /= ".")
        (splitDirectories loadedPath)
    descend accumulated component =
      case accumulated of
        Nothing -> Nothing
        Just retained
          | component /= ".." -> Just (component : retained)
          | otherwise ->
              case retained of
                -- An ascent past the filesystem root is not a path any loader
                -- could have opened.
                [] -> Nothing
                _ : above -> Just above

-- | The prefixes the operating system owns on a Linux substrate. A sealed
-- artifact is expected to load its own libraries and the platform C library,
-- and nothing else.
systemElfLibraryPath :: FilePath -> Bool
systemElfLibraryPath path =
  any
    (`List.isPrefixOf` path)
    [ "/lib/",
      "/lib64/",
      "/usr/lib/",
      "/usr/lib64/"
    ]

data DyldAuditLine
  = NotDyldAuditLine
  | -- | A @dyld@ frame that carries no loaded path. It is loader output, not
    -- application output, so it contributes neither loader provenance nor a
    -- line of the runner's own diagnostics.
    DyldSchedulingFrame
  | DyldLoadedPath !FilePath
  deriving (Eq, Show)

parseDyldAuditLine :: String -> Either String DyldAuditLine
parseDyldAuditLine rawLine =
  case dyldLinePayload (dropWhile isSpace rawLine) of
    Nothing -> Right NotDyldAuditLine
    Just payload
      -- Only a frame that announces itself as a load record is loader
      -- provenance. dyld emits a great deal of other commentary under the same
      -- prefix -- delayed-initialization transitions in both directions, and
      -- explanations such as "<lib> has weak-def (or flat lookup) symbol used
      -- by <lib>, so cannot be delayed". Enumerating those message shapes is
      -- brittle: each macOS release may add more, and two separate releases of
      -- this smoke were broken by exactly that. Such a frame carries no path
      -- and therefore contributes none.
      --
      -- Nothing is laundered by this. A path is only ever extracted from the
      -- load-record forms below, and a frame that /claims/ to be a load record
      -- but violates the shape still fails closed. The guarantee that the smoke
      -- actually observed its generation comes from the aggregate checks --
      -- at least one loaded path, at least one from the sealed artifact, and no
      -- unsealed non-system library -- so a future dyld that changed its load
      -- record format would fail loudly there rather than pass silently.
      | otherwise -> parseDyldLoadRecord payload

-- | A load record is exactly @\<uuid\> \/absolute\/canonical\/path@, or the
-- older @loaded: \/absolute\/canonical\/path@ spelling. Any other payload
-- carrying a @dyld[...]@ or @dyld:@ prefix fails closed rather than being
-- scanned for the first slash, so a frame this kernel does not understand can
-- never be laundered into a loaded path.
parseDyldLoadRecord :: String -> Either String DyldAuditLine
parseDyldLoadRecord payload =
  case payload of
    '<' : afterOpen ->
      case break (== '>') afterOpen of
        (uuid, '>' : afterUuid)
          | not (null uuid),
            all (\character -> isHexDigit character || character == '-') uuid ->
              validateLoadedPath (dropWhile isSpace afterUuid)
        _ -> malformed
    _ ->
      case List.stripPrefix "loaded: " payload of
        Just legacyPath -> validateLoadedPath (dropWhile isSpace legacyPath)
        -- Loader commentary rather than a load record: carries no path.
        Nothing -> Right DyldSchedulingFrame
  where
    malformed =
      Left
        ( "installed runner emitted malformed DYLD loader provenance: "
            <> show (take 200 payload)
        )
    validateLoadedPath loadedPath
      | not (isAbsolute loadedPath) = malformed
      | '\NUL' `elem` loadedPath =
          Left "installed runner DYLD loader provenance contains NUL"
      | normalise loadedPath /= loadedPath
          || ".." `elem` splitPathComponents loadedPath =
          Left "installed runner DYLD loader provenance is not canonical"
      | otherwise = Right (DyldLoadedPath loadedPath)

dyldLinePayload :: String -> Maybe String
dyldLinePayload line =
  case List.stripPrefix "dyld[" line of
    Just rest -> bracketedDyldPayload (span isDigit rest)
    Nothing ->
      dropWhile isSpace <$> List.stripPrefix "dyld:" line

-- | Accept a @dyld[<pid>]:@ frame only when the bracketed process id is a
-- bounded, non-empty digit run.
bracketedDyldPayload :: (String, String) -> Maybe String
bracketedDyldPayload (processDigits, suffix) =
  case suffix of
    ']' : ':' : payload
      | not (null processDigits)
          && length processDigits <= 20 ->
          Just (dropWhile isSpace payload)
    _ -> Nothing

classifyLoadedLibrary ::
  FilePath ->
  FilePath ->
  Either String (Maybe FilePath)
classifyLoadedLibrary executableSnapshotRoot loadedPath
  | systemDyldLibraryPath loadedPath = Right Nothing
  | otherwise =
      case sealedArtifactRootForPath executableSnapshotRoot loadedPath of
        Nothing ->
          Left
            ( "installed runner loaded an unsealed non-system library: "
                <> loadedPath
            )
        Just artifactRoot -> Right (Just artifactRoot)

systemDyldLibraryPath :: FilePath -> Bool
systemDyldLibraryPath path =
  any
    (`pathWithinOwnedRoot` path)
    systemDyldLibraryRoots

sealedArtifactRootForPath ::
  FilePath ->
  FilePath ->
  Maybe FilePath
sealedArtifactRootForPath executableSnapshotRoot loadedPath
  | not (pathWithinOwnedRoot executableSnapshotRoot loadedPath) = Nothing
  | otherwise =
      case splitPathComponents
        (makeRelative executableSnapshotRoot loadedPath) of
        generation : "artifact-root" : (_ : _)
          | safeSnapshotGenerationName generation ->
              Just
                ( executableSnapshotRoot
                    </> generation
                    </> "artifact-root"
                )
        _ -> Nothing

safeSnapshotGenerationName :: FilePath -> Bool
safeSnapshotGenerationName generation =
  not (null generation)
    && generation == takeFileName generation
    && generation /= "."
    && generation /= ".."
    && '\NUL' `notElem` generation

trimCapturedOutput :: String -> String
trimCapturedOutput =
  List.dropWhileEnd isSpace . dropWhile isSpace

-- | The byte-level counterpart of 'trimCapturedOutput', used to decide whether
-- a captured stream carries anything but ASCII whitespace.
trimCapturedBytes :: ByteString.ByteString -> ByteString.ByteString
trimCapturedBytes =
  ByteString8.dropWhileEnd isSpace . ByteString8.dropWhile isSpace

capturedCommandOutput :: String -> String -> String
capturedCommandOutput out err =
  "\nstdout:\n"
    <> out
    <> "\nstderr:\n"
    <> err

dispatchInternalSubprocessMode :: IO ()
dispatchInternalSubprocessMode = do
  arguments <- getArgs
  case arguments of
    [mode]
      | mode == internalAnchorMode ->
          runInternalAnchor
      | mode == internalSupervisorMode ->
          runInternalSupervisor
      | mode == internalPinMode ->
          runInternalPin
      | mode == internalProvisioningMutationMode ->
          runInternalProvisioningMutation
      | mode == internalSynchronousDescendantMode ->
          runInternalSynchronousDescendant
    [mode, identityPath]
      | mode == internalSynchronousTreeTargetMode ->
          runInternalSynchronousTreeTarget identityPath
    _ -> pure ()

runInternalSynchronousDescendant :: IO ()
runInternalSynchronousDescendant = do
  mapM_ prepareProtocolHandle [stdin, stdout, stderr]
  identity <-
    registerCurrentActivityIdentity
      "synchronous-exception self-exec descendant"
  writeJsonFrameHandle stdout (HelperIdentityReady identity)
  awaitHandleEof stdin

runInternalSynchronousTreeTarget :: FilePath -> IO ()
runInternalSynchronousTreeTarget identityPath = mask $ \restore -> do
  unless (isAbsolute identityPath && '\NUL' `notElem` identityPath) $
    ioError
      (userError "synchronous-exception identity target is not absolute")
  executable <- getExecutablePath
  termination <- newEmptyMVar
  previousHandler <-
    installHandler
      sigTERM
      (CatchOnce (void (tryPutMVar termination ())))
      Nothing
  -- This target was itself executed with the supervisor's explicit, validated
  -- target environment, so the descendant inherits that already-closed
  -- environment. Blanking it here would strip the HOME/TMPDIR the typed
  -- 'SubprocessEnv' guarantees, and reconstructing it would require reading
  -- the ambient environment, which the no-env doctrine forbids.
  (maybeInput, maybeOutput, maybeError, processHandle) <-
    createProcess
      (proc executable [internalSynchronousDescendantMode])
        { close_fds = True,
          create_group = False,
          env = Nothing,
          std_in = CreatePipe,
          std_out = CreatePipe,
          std_err = CreatePipe
        }
  let cleanup =
        runCleanupsPreservingFailures
          [ mapM_ (ignoreIOException . hClose) maybeInput,
            void (waitForProcessBounded processHandle),
            mapM_ (ignoreIOException . hClose) maybeOutput,
            mapM_
              ( \errorHandle -> do
                  _ <- readHandleToEnd maximumHelperDiagnosticBytes errorHandle
                  ignoreIOException (hClose errorHandle)
              )
              maybeError,
            void (installHandler sigTERM previousHandler Nothing)
          ]
  onExceptionPreservingPrimary
    ( restore $ do
        inputHandle <-
          maybe
            (ioError (userError "synchronous descendant has no custody input"))
            pure
            maybeInput
        outputHandle <-
          maybe
            (ioError (userError "synchronous descendant has no identity output"))
            pure
            maybeOutput
        identityEvent <-
          readJsonFrameHandle
            "synchronous descendant identity"
            outputHandle
        let HelperIdentityReady identity = identityEvent
        maybeProcessId <- getPid processHandle
        unless
          ( maybeProcessId
              == Just (fromIntegral (activityProcessId identity))
          )
          (ioError (userError "synchronous descendant ProcessHandle identity changed"))
        validateObservedGroupMember
          "synchronous self-exec descendant"
          identity
        publishSynchronousDescendantIdentity identityPath identity
        takeMVar termination
        hClose inputHandle
    )
    cleanup
  cleanup

publishSynchronousDescendantIdentity ::
  FilePath ->
  ActivityProcessIdentity ->
  IO ()
publishSynchronousDescendantIdentity identityPath identity = mask $ \restore -> do
  descriptor <-
    restore
      ( openFd
          identityPath
          WriteOnly
          defaultFileFlags
            { exclusive = True,
              nofollow = True,
              creat = Just commandActivityLeaseMode,
              cloexec = True
            }
      )
  finallyPreservingPrimary
    ( restore $ do
        writeRegularJsonFrameFd descriptor (HelperIdentityReady identity)
        fileSynchronise descriptor
    )
    (ignoreIOException (closeFd descriptor))
  synchroniseDirectory (takeDirectory identityPath)

-- | Render a wire-decode rejection as helper-visible text. Only an explicit
-- spec rejection carries its own message; every other outcome is an invalid
-- wire authority.
provisioningMutationWireRejection ::
  ProvisioningFilesystemMutationOutcome ->
  Text.Text
provisioningMutationWireRejection rejection =
  case rejection of
    ProvisioningMutationRejectedSpec failure -> failure
    _ -> "invalid provisioning mutation wire authority"

-- | Fold the isolated helper's mutation attempt into its wire outcome.
classifyProvisioningMutationHelperResult ::
  Either IOException (Either Text.Text ()) ->
  ProvisioningMutationHelperOutcome
classifyProvisioningMutationHelperResult result =
  case result of
    Left failure ->
      ProvisioningMutationHelperKernelFailure
        (Text.pack (displayException failure))
    Right (Left rejection) ->
      ProvisioningMutationHelperRejected rejection
    Right (Right ()) ->
      ProvisioningMutationHelperSucceeded

runInternalProvisioningMutation :: IO ()
runInternalProvisioningMutation = do
  mapM_ prepareProtocolHandle [stdin, stdout, stderr]
  requestBytes <-
    try @IOException
      (readHandleToEnd maximumProvisioningMutationRequestBytes stdin)
  helperOutcome <-
    case requestBytes of
      Left failure ->
        pure
          ( ProvisioningMutationHelperKernelFailure
              (Text.pack (displayException failure))
          )
      Right bytes ->
        case Aeson.eitherDecodeStrict' bytes of
          Left failure ->
            pure
              ( ProvisioningMutationHelperRejected
                  (Text.pack failure)
              )
          Right wireRequest ->
            case provisioningMutationFromWire wireRequest of
              Left rejection ->
                pure
                  ( ProvisioningMutationHelperRejected
                      (provisioningMutationWireRejection rejection)
                  )
              Right mutation -> do
                result <-
                  try @IOException
                    (executeProvisioningFilesystemMutation mutation)
                pure (classifyProvisioningMutationHelperResult result)
  ByteString.hPut
    stdout
    (LazyByteString.toStrict (Aeson.encode helperOutcome))
  hFlush stdout
  exitImmediately ExitSuccess

executeProvisioningFilesystemMutation ::
  ProvisioningFilesystemMutation ->
  IO (Either Text.Text ())
executeProvisioningFilesystemMutation mutation =
  withProvisioningMutationRootDescriptor
    (provisioningFilesystemMutationRoot mutation)
    ( \rootDescriptor -> do
        entryCounter <- newIORef 0
        withProvisioningMutationParentDescriptor
          rootDescriptor
          (provisioningFilesystemMutationParentComponents mutation)
          ( \parentDescriptor ->
              case mutation of
                ProvisioningCreateDirectoryLeaf _ _ leaf ->
                  createProvisioningMutationDirectory
                    parentDescriptor
                    leaf
                ProvisioningRemoveTreeLeaf _ _ leaf ->
                  removeProvisioningMutationTree
                    entryCounter
                    0
                    parentDescriptor
                    leaf
                ProvisioningRenameSiblingDirectory
                  _
                  _
                  sourceLeaf
                  destinationLeaf ->
                    renameProvisioningMutationDirectory
                      parentDescriptor
                      sourceLeaf
                      destinationLeaf
                ProvisioningRenameSiblingRegularFile
                  _
                  _
                  sourceLeaf
                  destinationLeaf ->
                    renameProvisioningMutationRegularFile
                      parentDescriptor
                      sourceLeaf
                      destinationLeaf
                ProvisioningReplaceSiblingRegularFile
                  _
                  _
                  sourceLeaf
                  destinationLeaf ->
                    replaceProvisioningMutationRegularFile
                      parentDescriptor
                      sourceLeaf
                      destinationLeaf
                ProvisioningCreateSymbolicLinkLeaf _ _ leaf target ->
                  createProvisioningMutationSymbolicLink
                    parentDescriptor
                    leaf
                    target
          )
    )

provisioningFilesystemMutationRoot ::
  ProvisioningFilesystemMutation ->
  ProvisioningMutationRoot
provisioningFilesystemMutationRoot mutation =
  case mutation of
    ProvisioningCreateDirectoryLeaf root _ _ -> root
    ProvisioningRemoveTreeLeaf root _ _ -> root
    ProvisioningRenameSiblingDirectory root _ _ _ -> root
    ProvisioningRenameSiblingRegularFile root _ _ _ -> root
    ProvisioningReplaceSiblingRegularFile root _ _ _ -> root
    ProvisioningCreateSymbolicLinkLeaf root _ _ _ -> root

provisioningFilesystemMutationParentComponents ::
  ProvisioningFilesystemMutation ->
  [FilePath]
provisioningFilesystemMutationParentComponents mutation =
  case mutation of
    ProvisioningCreateDirectoryLeaf _ components _ -> components
    ProvisioningRemoveTreeLeaf _ components _ -> components
    ProvisioningRenameSiblingDirectory _ components _ _ -> components
    ProvisioningRenameSiblingRegularFile _ components _ _ -> components
    ProvisioningReplaceSiblingRegularFile _ components _ _ -> components
    ProvisioningCreateSymbolicLinkLeaf _ components _ _ -> components

withProvisioningMutationRootDescriptor ::
  ProvisioningMutationRoot ->
  (Fd -> IO (Either Text.Text result)) ->
  IO (Either Text.Text result)
withProvisioningMutationRootDescriptor root action = mask $ \restore -> do
  listedStatus <- getSymbolicLinkStatus rootPath
  if not
    ( mutationRootStatusMatches root listedStatus
        && not (isSymbolicLink listedStatus)
    )
    then pure (Left "provisioning mutation root identity changed")
    else do
      descriptor <-
        restore
          ( openFd
              rootPath
              ReadOnly
              defaultFileFlags
                { nofollow = True,
                  directory = True,
                  cloexec = True
                }
          )
      finallyPreservingPrimary
        ( do
            openedStatus <- getFdStatus descriptor
            if not (mutationRootStatusMatches root openedStatus)
              then pure (Left "provisioning mutation root descriptor disagreed")
              else do
                result <- restore (action descriptor)
                finalDescriptorStatus <- getFdStatus descriptor
                finalPathStatus <- getSymbolicLinkStatus rootPath
                pure
                  ( if mutationRootStatusMatches root finalDescriptorStatus
                      && mutationRootStatusMatches root finalPathStatus
                      && not (isSymbolicLink finalPathStatus)
                      then result
                      else Left "provisioning mutation root changed during use"
                  )
        )
        (ignoreIOException (closeFd descriptor))
  where
    rootPath = provisioningMutationRootPath root

mutationRootStatusMatches ::
  ProvisioningMutationRoot ->
  FileStatus ->
  Bool
mutationRootStatusMatches root status =
  isDirectory status
    && fromIntegral (PosixFiles.deviceID status)
      == provisioningMutationRootDeviceId root
    && fromIntegral (PosixFiles.fileID status)
      == provisioningMutationRootFileId root
    && fromIntegral (fileMode status)
      == provisioningMutationRootMode root

withProvisioningMutationParentDescriptor ::
  Fd ->
  [FilePath] ->
  (Fd -> IO (Either Text.Text result)) ->
  IO (Either Text.Text result)
withProvisioningMutationParentDescriptor currentDescriptor components action =
  case components of
    [] -> do
      PosixDirectory.changeWorkingDirectoryFd currentDescriptor
      action currentDescriptor
    component : remaining -> do
      PosixDirectory.changeWorkingDirectoryFd currentDescriptor
      listedStatus <- getSymbolicLinkStatus component
      if not (isDirectory listedStatus && not (isSymbolicLink listedStatus))
        then pure (Left "provisioning mutation parent component is not a real directory")
        else mask $ \restore -> do
          childDescriptor <-
            restore
              ( openFdAt
                  (Just currentDescriptor)
                  component
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      directory = True,
                      cloexec = True
                    }
              )
          finallyPreservingPrimary
            ( do
                openedStatus <- getFdStatus childDescriptor
                if not (exactMutationDirectoryStatus listedStatus openedStatus)
                  then
                    pure
                      (Left "provisioning mutation parent component changed before open")
                  else do
                    result <-
                      restore
                        ( withProvisioningMutationParentDescriptor
                            childDescriptor
                            remaining
                            action
                        )
                    PosixDirectory.changeWorkingDirectoryFd currentDescriptor
                    finalNamedStatus <- getSymbolicLinkStatus component
                    finalOpenedStatus <- getFdStatus childDescriptor
                    pure
                      ( if exactMutationDirectoryStatus
                          openedStatus
                          finalOpenedStatus
                          && exactMutationDirectoryStatus
                            finalOpenedStatus
                            finalNamedStatus
                          && not (isSymbolicLink finalNamedStatus)
                          then result
                          else
                            Left
                              "provisioning mutation parent component changed during use"
                      )
            )
            (ignoreIOException (closeFd childDescriptor))

createProvisioningMutationDirectory ::
  Fd ->
  FilePath ->
  IO (Either Text.Text ())
createProvisioningMutationDirectory parentDescriptor leaf = do
  PosixDirectory.changeWorkingDirectoryFd parentDescriptor
  alreadyExists <- mutationPathExists leaf
  if alreadyExists
    then pure (Left "provisioning mutation directory leaf already exists")
    else do
      PosixDirectory.createDirectory leaf ownerModes
      createdStatus <- getSymbolicLinkStatus leaf
      if not (isDirectory createdStatus && not (isSymbolicLink createdStatus))
        then pure (Left "provisioning mutation created a non-directory leaf")
        else do
          fileSynchronise parentDescriptor
          pure (Right ())

-- | Create one symbolic link under the retained parent directory.
--
-- The parent descriptor is made the working directory first, so the leaf and
-- the created link are named relative to the exact directory object the caller
-- retained. The created link is read back and compared against the requested
-- target before the parent is fsynced, so a concurrent replacement between
-- creation and confirmation is a failure rather than a silent divergence.
createProvisioningMutationSymbolicLink ::
  Fd ->
  FilePath ->
  FilePath ->
  IO (Either Text.Text ())
createProvisioningMutationSymbolicLink parentDescriptor leaf target = do
  PosixDirectory.changeWorkingDirectoryFd parentDescriptor
  alreadyExists <- mutationPathExists leaf
  if alreadyExists
    then pure (Left "provisioning mutation link leaf already exists")
    else do
      createSymbolicLink target leaf
      createdStatus <- getSymbolicLinkStatus leaf
      createdTarget <- readSymbolicLink leaf
      if not (isSymbolicLink createdStatus) || createdTarget /= target
        then pure (Left "provisioning mutation created an unexpected link")
        else do
          fileSynchronise parentDescriptor
          pure (Right ())

renameProvisioningMutationDirectory ::
  Fd ->
  FilePath ->
  FilePath ->
  IO (Either Text.Text ())
renameProvisioningMutationDirectory
  parentDescriptor
  sourceLeaf
  destinationLeaf = do
    PosixDirectory.changeWorkingDirectoryFd parentDescriptor
    sourceStatus <- getSymbolicLinkStatus sourceLeaf
    destinationExists <- mutationPathExists destinationLeaf
    if
      | not (isDirectory sourceStatus && not (isSymbolicLink sourceStatus)) ->
          pure (Left "provisioning mutation rename source is not a real directory")
      | destinationExists ->
          pure (Left "provisioning mutation rename destination already exists")
      | otherwise -> mask $ \restore -> do
          sourceDescriptor <-
            restore
              ( openFdAt
                  (Just parentDescriptor)
                  sourceLeaf
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      directory = True,
                      cloexec = True
                    }
              )
          finallyPreservingPrimary
            ( do
                openedStatus <- getFdStatus sourceDescriptor
                if not (exactMutationDirectoryStatus sourceStatus openedStatus)
                  then pure (Left "provisioning mutation rename source changed")
                  else do
                    restore (PosixFiles.rename sourceLeaf destinationLeaf)
                    sourceStillExists <- mutationPathExists sourceLeaf
                    destinationStatus <-
                      getSymbolicLinkStatus destinationLeaf
                    finalOpenedStatus <- getFdStatus sourceDescriptor
                    if sourceStillExists
                      || isSymbolicLink destinationStatus
                      || not
                        ( exactMutationDirectoryStatus
                            openedStatus
                            finalOpenedStatus
                            && exactMutationDirectoryStatus
                              finalOpenedStatus
                              destinationStatus
                        )
                      then
                        pure
                          (Left "provisioning mutation sibling rename identity changed")
                      else do
                        fileSynchronise parentDescriptor
                        pure (Right ())
            )
            (ignoreIOException (closeFd sourceDescriptor))

renameProvisioningMutationRegularFile ::
  Fd ->
  FilePath ->
  FilePath ->
  IO (Either Text.Text ())
renameProvisioningMutationRegularFile
  parentDescriptor
  sourceLeaf
  destinationLeaf = do
    PosixDirectory.changeWorkingDirectoryFd parentDescriptor
    sourceStatus <- getSymbolicLinkStatus sourceLeaf
    destinationExists <- mutationPathExists destinationLeaf
    if
      | not (isRegularFile sourceStatus && not (isSymbolicLink sourceStatus)) ->
          pure (Left "provisioning mutation rename source is not a regular file")
      | destinationExists ->
          pure (Left "provisioning mutation rename destination already exists")
      | otherwise -> mask $ \restore -> do
          sourceDescriptor <-
            restore
              ( openFdAt
                  (Just parentDescriptor)
                  sourceLeaf
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      cloexec = True
                    }
              )
          finallyPreservingPrimary
            ( do
                openedStatus <- getFdStatus sourceDescriptor
                if not (exactMutationRegularFileStatus sourceStatus openedStatus)
                  then pure (Left "provisioning mutation rename source changed")
                  else do
                    fileSynchronise sourceDescriptor
                    restore (PosixFiles.rename sourceLeaf destinationLeaf)
                    sourceStillExists <- mutationPathExists sourceLeaf
                    destinationStatus <-
                      getSymbolicLinkStatus destinationLeaf
                    finalOpenedStatus <- getFdStatus sourceDescriptor
                    if sourceStillExists
                      || isSymbolicLink destinationStatus
                      || not
                        ( exactMutationRegularFileStatus
                            openedStatus
                            finalOpenedStatus
                            && exactMutationRegularFileStatus
                              finalOpenedStatus
                              destinationStatus
                        )
                      then
                        pure
                          (Left "provisioning mutation regular-file rename identity changed")
                      else do
                        fileSynchronise parentDescriptor
                        pure (Right ())
            )
            (ignoreIOException (closeFd sourceDescriptor))

-- | Atomically replace an existing regular-file sibling.
--
-- The destination must already be a real regular file: this operation exists
-- to make a durable-record replacement one step, and a caller that reached it
-- with an absent destination is publishing rather than replacing and should
-- have said so. The source's exact identity is retained across the rename and
-- confirmed at the destination afterwards, so a concurrent swap of either name
-- is a failure rather than a silently different published record.
replaceProvisioningMutationRegularFile ::
  Fd ->
  FilePath ->
  FilePath ->
  IO (Either Text.Text ())
replaceProvisioningMutationRegularFile
  parentDescriptor
  sourceLeaf
  destinationLeaf = do
    PosixDirectory.changeWorkingDirectoryFd parentDescriptor
    sourceStatus <- getSymbolicLinkStatus sourceLeaf
    destinationStatus <- try @IOException (getSymbolicLinkStatus destinationLeaf)
    if
      | not (isRegularFile sourceStatus && not (isSymbolicLink sourceStatus)) ->
          pure (Left "provisioning mutation replace source is not a regular file")
      | not (replacedRegularFileDestination destinationStatus) ->
          pure
            (Left "provisioning mutation replace destination is not a regular file")
      | otherwise -> mask $ \restore -> do
          sourceDescriptor <-
            restore
              ( openFdAt
                  (Just parentDescriptor)
                  sourceLeaf
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      cloexec = True
                    }
              )
          finallyPreservingPrimary
            ( do
                openedStatus <- getFdStatus sourceDescriptor
                if not (exactMutationRegularFileStatus sourceStatus openedStatus)
                  then pure (Left "provisioning mutation replace source changed")
                  else do
                    fileSynchronise sourceDescriptor
                    restore (PosixFiles.rename sourceLeaf destinationLeaf)
                    sourceStillExists <- mutationPathExists sourceLeaf
                    publishedStatus <-
                      getSymbolicLinkStatus destinationLeaf
                    finalOpenedStatus <- getFdStatus sourceDescriptor
                    if sourceStillExists
                      || isSymbolicLink publishedStatus
                      || not
                        ( exactMutationRegularFileStatus
                            openedStatus
                            finalOpenedStatus
                            && exactMutationRegularFileStatus
                              finalOpenedStatus
                              publishedStatus
                        )
                      then
                        pure
                          (Left "provisioning mutation replace identity changed")
                      else do
                        fileSynchronise parentDescriptor
                        pure (Right ())
            )
            (ignoreIOException (closeFd sourceDescriptor))

-- | Whether an observed replace destination is a real regular file.
replacedRegularFileDestination ::
  Either IOException FileStatus ->
  Bool
replacedRegularFileDestination observed =
  case observed of
    Left _ -> False
    Right status -> isRegularFile status && not (isSymbolicLink status)

exactMutationRegularFileStatus :: FileStatus -> FileStatus -> Bool
exactMutationRegularFileStatus expected observed =
  isRegularFile observed
    && not (isSymbolicLink observed)
    && sameFileObjectStatus expected observed
    && fileMode expected == fileMode observed
    && PosixFiles.fileSize expected == PosixFiles.fileSize observed

removeProvisioningMutationTree ::
  IORef Int ->
  Int ->
  Fd ->
  FilePath ->
  IO (Either Text.Text ())
removeProvisioningMutationTree entryCounter depth parentDescriptor leaf
  | depth > maximumProvisioningMutationDepth =
      pure (Left "provisioning mutation removal exceeded its depth bound")
  | otherwise = do
      withinBudget <- accountProvisioningMutationEntry entryCounter
      if not withinBudget
        then pure (Left "provisioning mutation removal exceeded its entry bound")
        else do
          PosixDirectory.changeWorkingDirectoryFd parentDescriptor
          statusResult <- try @IOException (getSymbolicLinkStatus leaf)
          case statusResult of
            Left failure
              | isDoesNotExistError failure -> pure (Right ())
              | otherwise -> ioError failure
            Right listedStatus
              | isDirectory listedStatus
                  && not (isSymbolicLink listedStatus) ->
                  removeProvisioningMutationDirectory
                    entryCounter
                    depth
                    parentDescriptor
                    leaf
                    listedStatus
              | isRegularFile listedStatus ->
                  removeProvisioningMutationRegularFile
                    parentDescriptor
                    leaf
                    listedStatus
              | isSymbolicLink listedStatus ->
                  removeProvisioningMutationSymlink
                    parentDescriptor
                    leaf
                    listedStatus
              | otherwise ->
                  pure
                    (Left "provisioning mutation removal encountered a special file")

removeProvisioningMutationDirectory ::
  IORef Int ->
  Int ->
  Fd ->
  FilePath ->
  FileStatus ->
  IO (Either Text.Text ())
removeProvisioningMutationDirectory
  entryCounter
  depth
  parentDescriptor
  leaf
  listedStatus = mask $ \restore -> do
    childDescriptor <-
      restore
        ( openFdAt
            (Just parentDescriptor)
            leaf
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        )
    finallyPreservingPrimary
      ( do
          openedStatus <- getFdStatus childDescriptor
          if not (exactMutationDirectoryStatus listedStatus openedStatus)
            then pure (Left "provisioning mutation directory changed before open")
            else do
              childNames <-
                restore
                  (listProvisioningMutationDirectory childDescriptor)
              removal <-
                foldM
                  ( \result childName ->
                      case result of
                        Left failure -> pure (Left failure)
                        Right () ->
                          removeProvisioningMutationTree
                            entryCounter
                            (depth + 1)
                            childDescriptor
                            childName
                  )
                  (Right ())
                  childNames
              case removal of
                Left failure -> pure (Left failure)
                Right () -> do
                  fileSynchronise childDescriptor
                  PosixDirectory.changeWorkingDirectoryFd parentDescriptor
                  finalNamedStatus <- getSymbolicLinkStatus leaf
                  finalOpenedStatus <- getFdStatus childDescriptor
                  if isSymbolicLink finalNamedStatus
                    || not
                      ( exactMutationDirectoryStatus
                          openedStatus
                          finalOpenedStatus
                          && exactMutationDirectoryStatus
                            finalOpenedStatus
                            finalNamedStatus
                      )
                    then
                      pure (Left "provisioning mutation directory changed before removal")
                    else do
                      restore (PosixDirectory.removeDirectory leaf)
                      fileSynchronise parentDescriptor
                      pure (Right ())
      )
      (ignoreIOException (closeFd childDescriptor))

removeProvisioningMutationRegularFile ::
  Fd ->
  FilePath ->
  FileStatus ->
  IO (Either Text.Text ())
removeProvisioningMutationRegularFile parentDescriptor leaf listedStatus =
  mask $ \restore -> do
    descriptor <-
      restore
        ( openFdAt
            (Just parentDescriptor)
            leaf
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                cloexec = True
              }
        )
    finallyPreservingPrimary
      ( do
          openedStatus <- getFdStatus descriptor
          if not
            ( isRegularFile openedStatus
                && sameFileObjectStatus listedStatus openedStatus
                && fileMode listedStatus == fileMode openedStatus
            )
            then pure (Left "provisioning mutation regular file changed before open")
            else do
              PosixDirectory.changeWorkingDirectoryFd parentDescriptor
              finalNamedStatus <- getSymbolicLinkStatus leaf
              if not
                ( isRegularFile finalNamedStatus
                    && sameFileObjectStatus openedStatus finalNamedStatus
                    && fileMode openedStatus == fileMode finalNamedStatus
                )
                then pure (Left "provisioning mutation regular file changed before removal")
                else do
                  restore (PosixFiles.removeLink leaf)
                  fileSynchronise parentDescriptor
                  pure (Right ())
      )
      (ignoreIOException (closeFd descriptor))

removeProvisioningMutationSymlink ::
  Fd ->
  FilePath ->
  FileStatus ->
  IO (Either Text.Text ())
removeProvisioningMutationSymlink parentDescriptor leaf listedStatus = do
  PosixDirectory.changeWorkingDirectoryFd parentDescriptor
  initialTarget <- readSymbolicLink leaf
  finalStatus <- getSymbolicLinkStatus leaf
  finalTarget <- readSymbolicLink leaf
  if not
    ( isSymbolicLink finalStatus
        && sameFileObjectStatus listedStatus finalStatus
        && fileMode listedStatus == fileMode finalStatus
        && initialTarget == finalTarget
    )
    then pure (Left "provisioning mutation symlink changed before removal")
    else do
      PosixFiles.removeLink leaf
      fileSynchronise parentDescriptor
      pure (Right ())

listProvisioningMutationDirectory :: Fd -> IO [FilePath]
listProvisioningMutationDirectory descriptor = mask $ \restore -> do
  duplicateDescriptor <- dup descriptor
  directoryStream <-
    onExceptionPreservingPrimary
      (unsafeOpenDirStreamFd duplicateDescriptor)
      (ignoreIOException (closeFd duplicateDescriptor))
  finallyPreservingPrimary
    (restore (collect directoryStream 0 []))
    (ignoreIOException (closeDirStream directoryStream))
  where
    collect directoryStream count entries = do
      entry <- readDirStream directoryStream
      if null entry
        then pure (List.sort entries)
        else
          if entry `elem` [".", ".."]
            then collect directoryStream count entries
            else
              if count >= maximumProvisioningMutationEntries
                || not (safeProvisioningMutationLeaf entry)
                then
                  ioError
                    ( userError
                        "provisioning mutation directory enumeration is invalid or over bound"
                    )
                else collect directoryStream (count + 1) (entry : entries)

accountProvisioningMutationEntry :: IORef Int -> IO Bool
accountProvisioningMutationEntry entryCounter =
  atomicModifyIORef' entryCounter $ \current ->
    let next = current + 1
     in (next, next <= maximumProvisioningMutationEntries)

mutationPathExists :: FilePath -> IO Bool
mutationPathExists path = do
  result <- try @IOException (getSymbolicLinkStatus path)
  case result of
    Right _ -> pure True
    Left failure
      | isDoesNotExistError failure -> pure False
      | otherwise -> ioError failure

runInternalAnchor :: IO ()
runInternalAnchor = do
  mapM_ prepareProtocolHandle [stdin, stdout, stderr]
  result <-
    try @SomeException $ do
      publishCurrentHelperIdentity "command anchor"
      superviseFromAnchor
  case result of
    Right exitCode -> exitImmediately exitCode
    Left failure -> do
      ignoreIOException
        ( writeJsonFrameHandle
            stdout
            ( AnchorKernelFailure
                ("runBoundedCommand anchor: " <> displayException failure)
            )
        )
      exitImmediately (ExitFailure 125)

superviseFromAnchor :: IO ExitCode
superviseFromAnchor = do
  plan <- Protocol.readAnchorConfiguration stdin
  validateAnchorSelfIdentity (supervisorPlanAnchorIdentity plan)
  withExactExecutableSnapshot plan supervisePreparedFromAnchor

supervisePreparedFromAnchor :: SupervisorPlan -> IO ExitCode
supervisePreparedFromAnchor plan = mask $ \restore -> do
  supervisor <-
    spawnSelfExecHelperWithGroup
      InheritHelperProcessGroup
      (supervisorPlanHelperEnvironment plan)
      internalSupervisorMode
  supervisorErrorResult <- newEmptyMVar
  void
    ( forkIO
        ( drainHandle
            maximumHelperDiagnosticBytes
            (spawnedHelperError supervisor)
            supervisorErrorResult
        )
    )
  supervisorFinalState <- newMVar Nothing
  pinProvisionalState <- newMVar Nothing
  targetGroupLeaderState <- newMVar Nothing
  let cleanupSupervisor =
        cleanupAnchorOwnedSupervisor
          (supervisorPlanReapEvidencePrefix plan)
          (supervisorPlanAnchorIdentity plan)
          supervisor
          supervisorFinalState
          pinProvisionalState
          targetGroupLeaderState
          supervisorErrorResult
      provisionalSupervisor =
        provisionalFromActivityIdentity
          (trackedHelperIdentity (spawnedHelperTracked supervisor))
      anchorGroup =
        activityProcessGroup (supervisorPlanAnchorIdentity plan)
  unless
    ( provisionalProcessGroup provisionalSupervisor == anchorGroup
        && provisionalProcessId provisionalSupervisor /= anchorGroup
    )
    ( finallyPreservingPrimary
        (ioError (userError "bounded-command supervisor was not born in anchor custody"))
        (void cleanupSupervisor)
    )
  runAnchorPrePublicationDeathHook
    plan
    supervisor
    provisionalSupervisor
  onExceptionPreservingPrimary
    ( restore $ do
        writeJsonFrameHandle
          stdout
          (AnchorSupervisorBorn provisionalSupervisor)
        Protocol.readAnchorSupervisorCustodyAck stdin
        writeJsonFrameHandle
          (spawnedHelperInput supervisor)
          (SupervisorConfigure plan)
        pinBornEvent <-
          awaitAnchorSupervisorEvent supervisor
        provisionalPin <-
          case pinBornEvent of
            Nothing -> do
              void cleanupSupervisor
              exitImmediately ExitSuccess
            Just (SupervisorPinBorn identity) -> pure identity
            Just unexpected ->
              ioError
                ( userError
                    ( "bounded-command supervisor skipped provisional pin custody: "
                        <> show unexpected
                    )
                )
        unless
          ( provisionalProcessGroup provisionalPin == anchorGroup
              && provisionalProcessId provisionalPin /= anchorGroup
              && provisionalProcessId provisionalPin
                /= provisionalProcessId provisionalSupervisor
          )
          (ioError (userError "bounded-command provisional pin escaped anchor custody"))
        modifyMVar_
          pinProvisionalState
          (const (pure (Just provisionalPin)))
        writeJsonFrameHandle
          stdout
          (AnchorPinBorn provisionalPin)
        Protocol.readAnchorPinCustodyAck stdin
        writeJsonFrameHandle
          (spawnedHelperInput supervisor)
          SupervisorAcknowledgePin
        writeJsonFrameHandle
          (spawnedHelperInput supervisor)
          SupervisorDetach
        detachedEvent <-
          awaitAnchorSupervisorEvent supervisor
        detachedSupervisor <-
          case detachedEvent of
            Nothing -> do
              void cleanupSupervisor
              exitImmediately ExitSuccess
            Just (SupervisorDetached identity) -> pure identity
            Just unexpected ->
              ioError
                ( userError
                    ( "bounded-command supervisor skipped its custody transition: "
                        <> show unexpected
                    )
                )
        validateCustodyTransition
          "supervisor"
          provisionalSupervisor
          detachedSupervisor
        modifyMVar_
          supervisorFinalState
          (const (pure (Just detachedSupervisor)))
        preparedEvent <-
          awaitAnchorSupervisorEvent supervisor
        targetGroupLeaderIdentity <-
          case preparedEvent of
            Nothing -> do
              void cleanupSupervisor
              exitImmediately ExitSuccess
            Just (SupervisorPrepared groupLeader) ->
              pure groupLeader
            Just unexpected ->
              ioError
                ( userError
                    ( "bounded-command supervisor sent an unexpected pre-prepare event: "
                        <> show unexpected
                    )
                )
        validateCustodyTransition
          "target-group pin"
          provisionalPin
          targetGroupLeaderIdentity
        modifyMVar_
          targetGroupLeaderState
          (const (pure (Just targetGroupLeaderIdentity)))
        writeJsonFrameHandle
          stdout
          ( AnchorSupervisorReady
              detachedSupervisor
              targetGroupLeaderIdentity
          )
        gateRequest <-
          try @IOException (Protocol.readAnchorStartGate stdin)
        case gateRequest of
          Left _ -> do
            void cleanupSupervisor
            pure ExitSuccess
          Right () -> do
            writeJsonFrameHandle
              (spawnedHelperInput supervisor)
              SupervisorOpenTargetGate
            wake <- newEmptyMVar
            void
              ( forkIO
                  ( try @IOException
                      ( readJsonFrameHandle
                          "supervisor event"
                          (spawnedHelperOutput supervisor)
                      )
                      >>= putMVar wake . AnchorSupervisorEvent
                  )
              )
            void
              ( forkIO
                  ( try @IOException
                      (Protocol.readAnchorStartGate stdin)
                      >>= putMVar wake . AnchorParentRequest
                  )
              )
            observedWake <- takeMVar wake
            case observedWake of
              AnchorParentRequest _ -> do
                void cleanupSupervisor
                pure ExitSuccess
              AnchorSupervisorEvent (Left failure) -> do
                ioError
                  ( userError
                      ( "bounded-command supervisor protocol failed: "
                          <> displayException failure
                      )
                  )
              AnchorSupervisorEvent (Right (SupervisorPrepared {})) ->
                ioError
                  (userError "bounded-command supervisor sent duplicate prepared event")
              AnchorSupervisorEvent (Right (SupervisorDetached {})) ->
                ioError
                  (userError "bounded-command supervisor sent duplicate detach event")
              AnchorSupervisorEvent (Right (SupervisorPinBorn {})) ->
                ioError
                  (userError "bounded-command supervisor sent duplicate pin-custody event")
              AnchorSupervisorEvent
                ( Right
                    ( SupervisorTerminal
                        terminal
                        inputEvidence
                        stdoutEvidence
                        stderrEvidence
                      )
                  ) -> do
                  (supervisorExit, _) <- cleanupSupervisor
                  let reportedSupervisorExit =
                        applySupervisorExitEvidenceFixture
                          (supervisorPlanProtocolEvidenceCase plan)
                          supervisorExit
                  writeJsonFrameHandle
                    stdout
                    ( AnchorTerminal
                        reportedSupervisorExit
                        terminal
                        inputEvidence
                        stdoutEvidence
                        stderrEvidence
                    )
                  pure ExitSuccess
    )
    (void cleanupSupervisor)

withExactExecutableSnapshot ::
  SupervisorPlan ->
  (SupervisorPlan -> IO result) ->
  IO result
withExactExecutableSnapshot plan usePlan =
  case supervisorPlanExecutableSnapshot plan of
    Nothing -> usePlan plan
    Just expectation ->
      mask $ \restore -> do
        let snapshotParent =
              supervisorPlanExecutableSnapshotRoot plan
            anchorIdentity =
              supervisorPlanAnchorIdentity plan
        unless
          ( validPackageClosureSnapshotAggregate
              (snapshotPackageClosures expectation)
              && validRuntimeLibrarySnapshotAggregate
                (snapshotRuntimeLibraries expectation)
          )
          (ioError (userError "bounded-command package/runtime closure aggregate is invalid"))
        prepareExecutableSnapshotParent snapshotParent
        recoverDeadExecutableSnapshots snapshotParent
        snapshotRoot <-
          createAnchorExecutableSnapshotRoot
            snapshotParent
            anchorIdentity
        let cleanup =
              removeAnchorExecutableSnapshotRoot
                snapshotRoot
                anchorIdentity
        ( snapshotExecutable,
          sealedExpectation,
          snapshotEnvironment,
          snapshotArguments,
          snapshotWorkingDirectory
          ) <-
          onExceptionPreservingPrimary
            ( do
                runExactExecutableSnapshotTestHook
                  MutateBeforeAnchorSnapshot
                  expectation
                packageClosures <-
                  zipWithM
                    (materializePackageClosureSnapshot snapshotRoot)
                    [0 ..]
                    (snapshotPackageClosures expectation)
                artifactSnapshot <-
                  artifactClosureSnapshotPair
                    (snapshotPackageClosures expectation)
                    packageClosures
                (executable, rewrittenArguments, rewrittenWorkingDirectory) <-
                  case artifactSnapshot of
                    Nothing -> do
                      standaloneExecutable <-
                        restore
                          ( materializeExactExecutableSnapshotUnlessPlatformBinary
                              snapshotRoot
                              expectation
                          )
                      pure
                        ( standaloneExecutable,
                          supervisorPlanArguments plan,
                          supervisorPlanWorkingDirectory plan
                        )
                    Just (sourceArtifact, sealedArtifact) ->
                      materializeArtifactSnapshotExecutable
                        expectation
                        sourceArtifact
                        sealedArtifact
                        (supervisorPlanArguments plan)
                        (supervisorPlanWorkingDirectory plan)
                runtimeLibraries <-
                  if SystemInfo.os == "linux"
                    then
                      mapM
                        ( \runtimeLibrary -> do
                            verifyRetainedRuntimeLibrary runtimeLibrary
                            pure runtimeLibrary
                        )
                        (snapshotRuntimeLibraries expectation)
                    else
                      mapM
                        (materializeRuntimeLibrarySnapshot snapshotRoot)
                        (snapshotRuntimeLibraries expectation)
                sealed <-
                  sealedExecutableSnapshotExpectation
                    executable
                    expectation
                    packageClosures
                    runtimeLibraries
                snapshotEnvironment <-
                  packageClosureSnapshotEnvironment
                    snapshotRoot
                    sealed
                    packageClosures
                    runtimeLibraries
                setFileMode
                  snapshotRoot
                  (ownerReadMode .|. ownerExecuteMode)
                synchroniseDirectory snapshotRoot
                synchroniseDirectory snapshotParent
                runExactExecutableSnapshotTestHook
                  MutateAfterAnchorSnapshot
                  expectation
                pure
                  ( executable,
                    sealed,
                    snapshotEnvironment,
                    rewrittenArguments,
                    rewrittenWorkingDirectory
                  )
            )
            cleanup
        finallyPreservingPrimary
          ( restore
              ( usePlan
                  plan
                    { supervisorPlanExecutable =
                        snapshotExecutable,
                      supervisorPlanExecutableSnapshot =
                        Just sealedExpectation,
                      -- The loader environment is rendered from this exact
                      -- per-anchor generation, not from its shared parent.
                      -- Carrying the parent here makes the helper re-derive
                      -- different Darwin framework/library paths.
                      supervisorPlanExecutableSnapshotRoot =
                        snapshotRoot,
                      supervisorPlanArguments =
                        snapshotArguments,
                      supervisorPlanEnvironment =
                        snapshotEnvironment
                          <> supervisorPlanEnvironment plan,
                      supervisorPlanWorkingDirectory =
                        snapshotWorkingDirectory
                    }
              )
          )
          cleanup

runExactExecutableSnapshotTestHook ::
  ExactExecutableSnapshotTestPoint ->
  ExecutableSnapshotExpectation ->
  IO ()
runExactExecutableSnapshotTestHook expectedPoint expectation =
  case snapshotTestHook expectation of
    Just hook
      | snapshotTestPoint hook == expectedPoint -> do
          release <-
            readNamedPipePayloadAfterReady
              (snapshotTestReadyPath hook)
              (snapshotTestReleasePath hook)
          unless
            (release == "release\n")
            (ioError (userError "exact executable snapshot test release was invalid"))
    _ -> pure ()

prepareExecutableSnapshotParent :: FilePath -> IO ()
prepareExecutableSnapshotParent snapshotParent = do
  createResult <-
    try (createDirectory snapshotParent) ::
      IO (Either IOException ())
  case createResult of
    Right () -> synchroniseDirectory (takeDirectory snapshotParent)
    Left failure
      | isAlreadyExistsError failure -> pure ()
      | otherwise -> ioError failure
  status <- getSymbolicLinkStatus snapshotParent
  unless
    (isDirectory status && not (isSymbolicLink status))
    ( ioError
        ( userError
            ( "bounded-command executable snapshot parent is not a real directory: "
                <> snapshotParent
            )
        )
    )
  setFileMode snapshotParent ownerModes
  synchroniseDirectory snapshotParent

createAnchorExecutableSnapshotRoot ::
  FilePath ->
  ActivityProcessIdentity ->
  IO FilePath
createAnchorExecutableSnapshotRoot snapshotParent anchorIdentity = do
  let snapshotRoot =
        snapshotParent
          </> executableSnapshotOwnerName anchorIdentity
  createDirectory snapshotRoot
  setFileMode snapshotRoot ownerModes
  synchroniseDirectory snapshotParent
  writeExecutableSnapshotOwner snapshotRoot anchorIdentity
  pure snapshotRoot

executableSnapshotOwnerName :: ActivityProcessIdentity -> FilePath
executableSnapshotOwnerName identity =
  ".anchor-"
    <> show (activityProcessId identity)
    <> "-"
    <> ByteString8.unpack
      ( Base16.encode
          ( ByteString8.pack
              (renderProcessBirthIdentity (activityProcessBirthIdentity identity))
          )
      )

writeExecutableSnapshotOwner ::
  FilePath ->
  ActivityProcessIdentity ->
  IO ()
writeExecutableSnapshotOwner snapshotRoot identity =
  mask $ \restore -> do
    let ownerPath = snapshotRoot </> "owner.identity"
        contents =
          ByteString8.pack
            ( show (activityProcessId identity)
                <> "\n"
                <> show (activityProcessGroup identity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity identity)
                <> "\n"
            )
    descriptor <-
      openFd
        ownerPath
        WriteOnly
        defaultFileFlags
          { exclusive = True,
            nofollow = True,
            creat = Just commandActivityLeaseMode,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          writeFdFullyBlocking descriptor contents
          fileSynchronise descriptor
      )
      (ignoreIOException (closeFd descriptor))
    setFileMode ownerPath ownerReadMode
    synchroniseDirectory snapshotRoot

-- | Sweep abandoned snapshot roots whose owner is provably dead.
--
-- The owning helper retires its own snapshot in its own cleanup, so this sweep
-- races that teardown by construction. An entry — or its owner record — that
-- disappears under the sweep is being retired by its rightful owner and is not
-- a fault: the sweep skips it and leaves the owner's own retirement to report.
recoverDeadExecutableSnapshots :: FilePath -> IO ()
recoverDeadExecutableSnapshots snapshotParent =
  mask $ \restore -> do
    listedParentStatus <- getSymbolicLinkStatus snapshotParent
    parentDescriptor <-
      openFd
        snapshotParent
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          openedParentStatus <- getFdStatus parentDescriptor
          unless
            ( isDirectory openedParentStatus
                && not (isSymbolicLink listedParentStatus)
                && exactFileStatusMatches
                  listedParentStatus
                  openedParentStatus
            )
            (ioError (userError "bounded-command snapshot parent changed before recovery"))
          entries <-
            listDirectoryBoundedFromDescriptor
              parentDescriptor
              maximumExecutableSnapshotRecoveryGenerations
          mapM_ (recoverEntryIgnoringConcurrentRetirement parentDescriptor) entries
          finalParentStatus <- getFdStatus parentDescriptor
          finalParentPathStatus <- getSymbolicLinkStatus snapshotParent
          unless
            ( sameFileObjectStatus openedParentStatus finalParentStatus
                && sameFileObjectStatus
                  finalParentStatus
                  finalParentPathStatus
            )
            (ioError (userError "bounded-command snapshot parent changed during recovery"))
      )
      (ignoreIOException (closeFd parentDescriptor))
  where
    recoverEntryIgnoringConcurrentRetirement parentDescriptor entry = do
      observed <-
        try @IOException (recoverEntry parentDescriptor entry)
      case observed of
        Right () -> pure ()
        Left failure
          | isDoesNotExistError failure -> pure ()
          | otherwise -> ioError failure

    recoverEntry parentDescriptor entry =
      case parseExecutableSnapshotOwnerName entry of
        Nothing ->
          ioError
            ( userError
                ( "unexpected entry in bounded-command executable snapshot root: "
                    <> (snapshotParent </> entry)
                )
            )
        Just (processId, birthIdentity) -> do
          let snapshotRoot = snapshotParent </> entry
          rootDescriptor <-
            openFdAt
              (Just parentDescriptor)
              entry
              ReadOnly
              defaultFileFlags
                { nofollow = True,
                  directory = True,
                  cloexec = True
                }
          (ownerIdentity, observedRootStatus) <-
            finallyPreservingPrimary
              ( do
                  status <- getFdStatus rootDescriptor
                  pathStatus <- getSymbolicLinkStatus snapshotRoot
                  unless
                    ( isDirectory status
                        && not (isSymbolicLink pathStatus)
                        && exactFileStatusMatches status pathStatus
                    )
                    ( ioError
                        ( userError
                            ( "bounded-command executable snapshot entry is not a stable real directory: "
                                <> snapshotRoot
                            )
                        )
                    )
                  owner <-
                    readExecutableSnapshotOwnerAt
                      snapshotRoot
                      rootDescriptor
                  pure (owner, status)
              )
              (ignoreIOException (closeFd rootDescriptor))
          unless
            ( activityProcessId ownerIdentity == processId
                && activityProcessBirthIdentity ownerIdentity
                  == birthIdentity
                && executableSnapshotOwnerName ownerIdentity == entry
            )
            (ioError (userError "bounded-command executable snapshot owner name and record disagree"))
          currentIdentity <- readProcessBirthIdentity processId
          unless
            (currentIdentity == Just birthIdentity)
            ( removeRecoveredExecutableSnapshot
                snapshotRoot
                ownerIdentity
                observedRootStatus
            )

parseExecutableSnapshotOwnerName ::
  FilePath ->
  Maybe (Integer, ProcessBirthIdentity)
parseExecutableSnapshotOwnerName entry = do
  suffix <- List.stripPrefix ".anchor-" entry
  let (processIdText, encodedSuffix) = span isDigit suffix
  encodedIdentity <-
    case encodedSuffix of
      '-' : value
        | not (null value) && all isHexDigit value ->
            Just value
      _ -> Nothing
  processId <- readMaybe processIdText
  guard (processId > 0 && processId <= 2147483647)
  decoded <-
    either
      (const Nothing)
      Just
      (Base16.decode (ByteString8.pack encodedIdentity))
  birthIdentity <-
    parseProcessBirthIdentity (ByteString8.unpack decoded)
  pure (processId, birthIdentity)

maximumExecutableSnapshotRecoveryGenerations :: Integer
maximumExecutableSnapshotRecoveryGenerations = 64

maximumExecutableSnapshotRecoveryEntries :: Integer
maximumExecutableSnapshotRecoveryEntries =
  maximumPackageClosureSnapshotFiles
    + fromIntegral maximumRuntimeLibrarySnapshots
    + 1024

maximumExecutableSnapshotRecoveryBytes :: Integer
maximumExecutableSnapshotRecoveryBytes =
  maximumExecutableSnapshotBytes
    + maximumPackageClosureSnapshotBytes
    + maximumRuntimeLibrarySnapshotBytes
    + 1024 * 1024

maximumExecutableSnapshotRecoveryDepth :: Int
maximumExecutableSnapshotRecoveryDepth =
  maximumPackageClosureSnapshotDepth + 8

data ExecutableSnapshotRecoveryBudget = ExecutableSnapshotRecoveryBudget
  { executableSnapshotRecoveryEntries :: !Integer,
    executableSnapshotRecoveryBytes :: !Integer
  }

removeRecoveredExecutableSnapshot ::
  FilePath ->
  ActivityProcessIdentity ->
  FileStatus ->
  IO ()
removeRecoveredExecutableSnapshot snapshotRoot expectedOwner expectedRootStatus =
  mask_ $ do
    let snapshotParent = takeDirectory snapshotRoot
        snapshotEntry = takeFileName snapshotRoot
    parentDescriptor <-
      openFd
        snapshotParent
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( do
          parentStatus <- getFdStatus parentDescriptor
          parentPathStatus <- getSymbolicLinkStatus snapshotParent
          unless
            ( isDirectory parentStatus
                && not (isSymbolicLink parentPathStatus)
                && exactFileStatusMatches parentStatus parentPathStatus
            )
            (ioError (userError "bounded-command snapshot parent changed before cleanup"))
          rootDescriptor <-
            openFdAt
              (Just parentDescriptor)
              snapshotEntry
              ReadOnly
              defaultFileFlags
                { nofollow = True,
                  directory = True,
                  cloexec = True
                }
          finallyPreservingPrimary
            ( do
                rootStatus <- getFdStatus rootDescriptor
                rootPathStatus <- getSymbolicLinkStatus snapshotRoot
                unless
                  ( exactFileStatusMatches expectedRootStatus rootStatus
                      && isDirectory rootStatus
                      && not (isSymbolicLink rootPathStatus)
                      && exactFileStatusMatches rootStatus rootPathStatus
                  )
                  (ioError (userError "bounded-command snapshot root changed before cleanup"))
                ownerIdentity <-
                  readExecutableSnapshotOwnerAt
                    snapshotRoot
                    rootDescriptor
                unless
                  ( ownerIdentity == expectedOwner
                      && executableSnapshotOwnerName ownerIdentity
                        == snapshotEntry
                  )
                  (ioError (userError "bounded-command snapshot cleanup owner changed"))
                PosixFiles.setFdMode rootDescriptor ownerModes
                _ <-
                  removeExecutableSnapshotDirectoryEntries
                    snapshotRoot
                    rootDescriptor
                    0
                    ExecutableSnapshotRecoveryBudget
                      { executableSnapshotRecoveryEntries = 0,
                        executableSnapshotRecoveryBytes = 0
                      }
                finalRootStatus <- getFdStatus rootDescriptor
                finalRootPathStatus <- getSymbolicLinkStatus snapshotRoot
                unless
                  ( sameFileObjectStatus rootStatus finalRootStatus
                      && sameFileObjectStatus
                        finalRootStatus
                        finalRootPathStatus
                  )
                  (ioError (userError "bounded-command snapshot root changed during cleanup"))
                removeDirectory snapshotRoot
                finalParentStatus <- getFdStatus parentDescriptor
                unless
                  (sameFileObjectStatus parentStatus finalParentStatus)
                  (ioError (userError "bounded-command snapshot parent changed during cleanup"))
                synchroniseDirectory snapshotParent
            )
            (ignoreIOException (closeFd rootDescriptor))
      )
      (ignoreIOException (closeFd parentDescriptor))

removeExecutableSnapshotDirectoryEntries ::
  FilePath ->
  Fd ->
  Int ->
  ExecutableSnapshotRecoveryBudget ->
  IO ExecutableSnapshotRecoveryBudget
removeExecutableSnapshotDirectoryEntries directoryPath descriptor depth budget = do
  unless
    (depth <= maximumExecutableSnapshotRecoveryDepth)
    (ioError (userError "bounded-command snapshot cleanup exceeds its depth bound"))
  entries <-
    listDirectoryBoundedFromDescriptor
      descriptor
      ( maximumExecutableSnapshotRecoveryEntries
          - executableSnapshotRecoveryEntries budget
      )
  foldM
    (removeExecutableSnapshotEntry directoryPath descriptor depth)
    budget
    entries

removeExecutableSnapshotEntry ::
  FilePath ->
  Fd ->
  Int ->
  ExecutableSnapshotRecoveryBudget ->
  FilePath ->
  IO ExecutableSnapshotRecoveryBudget
removeExecutableSnapshotEntry
  parentPath
  parentDescriptor
  parentDepth
  budget
  entry = do
    let path = parentPath </> entry
        countedBudget =
          budget
            { executableSnapshotRecoveryEntries =
                executableSnapshotRecoveryEntries budget + 1
            }
    requireExecutableSnapshotRecoveryBudget countedBudget
    directoryResult <-
      try @IOException
        ( openFdAt
            (Just parentDescriptor)
            entry
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        )
    case directoryResult of
      Right childDescriptor ->
        finallyPreservingPrimary
          ( do
              childStatus <- getFdStatus childDescriptor
              childPathStatus <- getSymbolicLinkStatus path
              unless
                ( isDirectory childStatus
                    && not (isSymbolicLink childPathStatus)
                    && exactFileStatusMatches childStatus childPathStatus
                )
                (ioError (userError ("snapshot cleanup directory changed: " <> path)))
              PosixFiles.setFdMode childDescriptor ownerModes
              nextBudget <-
                removeExecutableSnapshotDirectoryEntries
                  path
                  childDescriptor
                  (parentDepth + 1)
                  countedBudget
              finalChildStatus <- getFdStatus childDescriptor
              reopenedChildStatus <-
                reopenSnapshotDirectoryEntryStatus
                  parentDescriptor
                  entry
              unless
                ( sameFileObjectStatus childStatus finalChildStatus
                    && sameFileObjectStatus
                      finalChildStatus
                      reopenedChildStatus
                )
                (ioError (userError ("snapshot cleanup directory identity changed: " <> path)))
              removeDirectory path
              pure nextBudget
          )
          (ignoreIOException (closeFd childDescriptor))
      Left _ ->
        removeExecutableSnapshotNonDirectory
          parentPath
          parentDescriptor
          path
          entry
          countedBudget

removeExecutableSnapshotNonDirectory ::
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  ExecutableSnapshotRecoveryBudget ->
  IO ExecutableSnapshotRecoveryBudget
removeExecutableSnapshotNonDirectory
  parentPath
  parentDescriptor
  path
  entry
  budget = do
    fileResult <-
      try @IOException
        ( openFdAt
            (Just parentDescriptor)
            entry
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                nonBlock = True,
                cloexec = True
              }
        )
    case fileResult of
      Right fileDescriptor ->
        finallyPreservingPrimary
          ( do
              status <- getFdStatus fileDescriptor
              pathStatus <- getSymbolicLinkStatus path
              unless
                ( isRegularFile status
                    && exactFileStatusMatches status pathStatus
                )
                (ioError (userError ("snapshot cleanup encountered unsupported entry: " <> path)))
              let nextBudget =
                    budget
                      { executableSnapshotRecoveryBytes =
                          executableSnapshotRecoveryBytes budget
                            + fromIntegral (PosixFiles.fileSize status)
                      }
              requireExecutableSnapshotRecoveryBudget nextBudget
              finalStatus <- getFdStatus fileDescriptor
              finalPathStatus <- getSymbolicLinkStatus path
              unless
                ( exactFileStatusMatches status finalStatus
                    && exactFileStatusMatches finalStatus finalPathStatus
                )
                (ioError (userError ("snapshot cleanup file changed: " <> path)))
              removeFile path
              pure nextBudget
          )
          (ignoreIOException (closeFd fileDescriptor))
      Left _ ->
        removeExecutableSnapshotLink
          parentPath
          parentDescriptor
          path
          budget

removeExecutableSnapshotLink ::
  FilePath ->
  Fd ->
  FilePath ->
  ExecutableSnapshotRecoveryBudget ->
  IO ExecutableSnapshotRecoveryBudget
removeExecutableSnapshotLink parentPath parentDescriptor path budget = do
  parentStatus <- getFdStatus parentDescriptor
  parentPathStatus <- getSymbolicLinkStatus parentPath
  unless
    (sameFileObjectStatus parentStatus parentPathStatus)
    (ioError (userError ("snapshot cleanup parent changed: " <> parentPath)))
  status <- getSymbolicLinkStatus path
  unless
    (isSymbolicLink status)
    (ioError (userError ("snapshot cleanup entry is neither regular nor a link: " <> path)))
  target <- readSymbolicLink path
  finalStatus <- getSymbolicLinkStatus path
  finalTarget <- readSymbolicLink path
  finalParentStatus <- getFdStatus parentDescriptor
  finalParentPathStatus <- getSymbolicLinkStatus parentPath
  unless
    ( exactFileStatusMatches status finalStatus
        && target == finalTarget
        && sameFileObjectStatus parentStatus finalParentStatus
        && sameFileObjectStatus
          finalParentStatus
          finalParentPathStatus
    )
    (ioError (userError ("snapshot cleanup link changed: " <> path)))
  let nextBudget =
        budget
          { executableSnapshotRecoveryBytes =
              executableSnapshotRecoveryBytes budget
                + fromIntegral
                  ( ByteString.length
                      (TextEncoding.encodeUtf8 (Text.pack target))
                  )
          }
  requireExecutableSnapshotRecoveryBudget nextBudget
  removeFile path
  pure nextBudget

requireExecutableSnapshotRecoveryBudget ::
  ExecutableSnapshotRecoveryBudget ->
  IO ()
requireExecutableSnapshotRecoveryBudget budget =
  unless
    ( executableSnapshotRecoveryEntries budget
        <= maximumExecutableSnapshotRecoveryEntries
        && executableSnapshotRecoveryBytes budget
          <= maximumExecutableSnapshotRecoveryBytes
    )
    (ioError (userError "bounded-command snapshot cleanup exceeds its global bound"))

reopenSnapshotDirectoryEntryStatus :: Fd -> FilePath -> IO FileStatus
reopenSnapshotDirectoryEntryStatus parentDescriptor entry =
  mask $ \restore -> do
    descriptor <-
      openFdAt
        (Just parentDescriptor)
        entry
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    finallyPreservingPrimary
      (restore (getFdStatus descriptor))
      (ignoreIOException (closeFd descriptor))

removeAnchorExecutableSnapshotRoot ::
  FilePath ->
  ActivityProcessIdentity ->
  IO ()
removeAnchorExecutableSnapshotRoot snapshotRoot anchorIdentity = do
  unless
    ( takeFileName snapshotRoot
        == executableSnapshotOwnerName anchorIdentity
    )
    ( ioError
        (userError "bounded-command executable snapshot cleanup owner disagreed")
    )
  observedRootStatus <-
    observeExecutableSnapshotRoot
      snapshotRoot
      anchorIdentity
  removeRecoveredExecutableSnapshot
    snapshotRoot
    anchorIdentity
    observedRootStatus

observeExecutableSnapshotRoot ::
  FilePath ->
  ActivityProcessIdentity ->
  IO FileStatus
observeExecutableSnapshotRoot snapshotRoot expectedOwner =
  mask $ \restore -> do
    listedStatus <- getSymbolicLinkStatus snapshotRoot
    descriptor <-
      openFd
        snapshotRoot
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          status <- getFdStatus descriptor
          unless
            ( isDirectory status
                && not (isSymbolicLink listedStatus)
                && exactFileStatusMatches listedStatus status
            )
            (ioError (userError "bounded-command owned snapshot root changed"))
          owner <- readExecutableSnapshotOwnerAt snapshotRoot descriptor
          unless
            ( owner == expectedOwner
                && executableSnapshotOwnerName owner
                  == takeFileName snapshotRoot
            )
            (ioError (userError "bounded-command owned snapshot identity disagreed"))
          finalStatus <- getFdStatus descriptor
          finalPathStatus <- getSymbolicLinkStatus snapshotRoot
          unless
            ( exactFileStatusMatches status finalStatus
                && exactFileStatusMatches finalStatus finalPathStatus
            )
            (ioError (userError "bounded-command owned snapshot root changed during observation"))
          pure finalStatus
      )
      (ignoreIOException (closeFd descriptor))

readExecutableSnapshotOwnerAt ::
  FilePath ->
  Fd ->
  IO ActivityProcessIdentity
readExecutableSnapshotOwnerAt snapshotRoot rootDescriptor = do
  let ownerPath = snapshotRoot </> "owner.identity"
  descriptor <-
    openFdAt
      (Just rootDescriptor)
      "owner.identity"
      ReadOnly
      defaultFileFlags
        { nofollow = True,
          nonBlock = True,
          cloexec = True
        }
  contents <-
    finallyPreservingPrimary
      ( do
          status <- getFdStatus descriptor
          pathStatus <- getSymbolicLinkStatus ownerPath
          unless
            ( isRegularFile status
                && exactFileStatusMatches status pathStatus
                && PosixFiles.fileSize status <= 4096
            )
            (ioError (userError ("snapshot owner record is invalid: " <> ownerPath)))
          observed <- readSnapshotOwnerDescriptor descriptor 0 []
          finalStatus <- getFdStatus descriptor
          finalPathStatus <- getSymbolicLinkStatus ownerPath
          unless
            ( exactFileStatusMatches status finalStatus
                && exactFileStatusMatches finalStatus finalPathStatus
                && ByteString.length observed
                  == fromIntegral (PosixFiles.fileSize status)
            )
            (ioError (userError ("snapshot owner record changed: " <> ownerPath)))
          pure observed
      )
      (ignoreIOException (closeFd descriptor))
  case ByteString8.lines contents of
    [processIdText, processGroupText, birthIdentityText]
      | Just processId <- readMaybe (ByteString8.unpack processIdText),
        Just processGroup <- readMaybe (ByteString8.unpack processGroupText),
        Just birthIdentity <-
          parseProcessBirthIdentity (ByteString8.unpack birthIdentityText),
        processId > 0,
        processGroup > 0 ->
          pure
            ActivityProcessIdentity
              { activityProcessId = processId,
                activityProcessGroup = processGroup,
                activityProcessBirthIdentity = birthIdentity
              }
    _ ->
      ioError
        ( userError
            ( "bounded-command executable snapshot owner record is invalid: "
                <> ownerPath
            )
        )

readSnapshotOwnerDescriptor ::
  Fd ->
  Int ->
  [ByteString.ByteString] ->
  IO ByteString.ByteString
readSnapshotOwnerDescriptor descriptor bytesRead chunks
  | bytesRead > 4096 =
      ioError (userError "snapshot owner record exceeds its fixed byte bound")
  | otherwise = do
      chunk <-
        readRegularFdChunk
          descriptor
          (fromIntegral (4097 - bytesRead))
      if ByteString.null chunk
        then pure (ByteString.concat (reverse chunks))
        else
          readSnapshotOwnerDescriptor
            descriptor
            (bytesRead + ByteString.length chunk)
            (chunk : chunks)

-- | Snapshot the target executable, unless it is an operating-system platform
-- binary, which is executed in place after the same identity validation.
--
-- On Apple Silicon a platform binary is validated against the kernel trust
-- cache rather than an embedded signature, so a /copy/ of one carries no usable
-- signature and the kernel kills it at exec: a copied @\/usr\/bin\/curl@ dies
-- with @SIGKILL@ and produces no output, while the original runs normally.
-- Snapshotting therefore cannot be applied to @curl@, @hdiutil@, @ditto@,
-- @top@, @footprint@, or any other configured system tool.
--
-- Executing such a binary in place is not a weakening. The snapshot exists to
-- stop the executable being swapped between validation and exec, and a
-- SIP-protected path cannot be swapped at all without disabling System
-- Integrity Protection -- a stronger guarantee than a private copy. The exact
-- identity checks are unchanged: the canonical path, device, inode, mode, size,
-- and content digest are all still verified against the recorded expectation
-- immediately before launch. Only paths the operating system itself protects
-- qualify; @\/usr\/local@ and Homebrew prefixes are writable and continue to be
-- snapshotted.
materializeExactExecutableSnapshotUnlessPlatformBinary ::
  FilePath ->
  ExecutableSnapshotExpectation ->
  IO FilePath
materializeExactExecutableSnapshotUnlessPlatformBinary snapshotRoot expectation
  | systemPlatformBinaryPath (snapshotCanonicalPath expectation) = do
      canonicalPath <-
        canonicalizePath (snapshotConfiguredPath expectation)
      unless
        (normalise canonicalPath == normalise (snapshotCanonicalPath expectation))
        ( ioError
            ( userError
                "bounded-command configured executable canonical target changed before platform-binary launch"
            )
        )
      observedStatus <- getSymbolicLinkStatus canonicalPath
      unless
        (exactExecutableStatusMatches expectation observedStatus)
        ( ioError
            ( userError
                "bounded-command platform binary identity changed before launch"
            )
        )
      pure canonicalPath
  | otherwise = materializeExactExecutableSnapshot snapshotRoot expectation

-- | Absolute path prefixes the operating system protects and whose executables
-- are trust-cache platform binaries.
systemPlatformBinaryPath :: FilePath -> Bool
systemPlatformBinaryPath path =
  isAbsolute path
    && any
      (`pathWithinOwnedRoot` normalise path)
      systemPlatformExecutableRoots

materializeExactExecutableSnapshot ::
  FilePath ->
  ExecutableSnapshotExpectation ->
  IO FilePath
materializeExactExecutableSnapshot snapshotRoot expectation =
  mask $ \restore -> do
    canonicalPath <-
      restore (canonicalizePath (snapshotConfiguredPath expectation))
    unless
      (normalise canonicalPath == normalise (snapshotCanonicalPath expectation))
      ( ioError
          ( userError
              "bounded-command configured executable canonical target changed before anchor snapshot"
          )
      )
    sourceDescriptor <-
      openFd
        (snapshotCanonicalPath expectation)
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    -- Keep the executable's own filename inside the snapshot rather than
    -- renaming it to a fixed leaf. A target that records its own path durably
    -- would otherwise persist the synthetic name: `python -m venv` writes
    -- `executable = <snapshotRoot>/target` into the venv's `pyvenv.cfg`, which
    -- both names an ephemeral path and leaves the artifact's own relocation
    -- unable to recover the real interpreter leaf.
    snapshotLeaf <-
      case takeFileName (snapshotCanonicalPath expectation) of
        leaf
          | safeProvisioningMutationLeaf leaf -> pure leaf
          | otherwise ->
              ioError
                ( userError
                    "bounded-command executable snapshot source has an unsafe filename"
                )
    let snapshotPath = snapshotRoot </> snapshotLeaf
    finallyPreservingPrimary
      ( do
          openedStatus <- getFdStatus sourceDescriptor
          unless
            (exactExecutableStatusMatches expectation openedStatus)
            ( ioError
                ( userError
                    "bounded-command executable identity changed before anchor snapshot"
                )
            )
          targetDescriptor <-
            openFd
              snapshotPath
              ReadWrite
              defaultFileFlags
                { exclusive = True,
                  nofollow = True,
                  creat = Just commandActivityLeaseMode,
                  cloexec = True
                }
          finallyPreservingPrimary
            ( restore $ do
                openedTargetStatus <- getFdStatus targetDescriptor
                unless
                  (isRegularFile openedTargetStatus)
                  (ioError (userError "bounded-command executable snapshot target is not regular"))
                (copiedBytes, digestContext) <-
                  copyExecutableDescriptor
                    sourceDescriptor
                    targetDescriptor
                    (snapshotSize expectation)
                    0
                    SHA256.init
                finalSourceStatus <- getFdStatus sourceDescriptor
                finalPathStatus <-
                  getSymbolicLinkStatus
                    (snapshotCanonicalPath expectation)
                let observedDigest =
                      "sha256:"
                        <> TextEncoding.decodeUtf8
                          (Base16.encode (SHA256.finalize digestContext))
                unless
                  ( exactExecutableStatusMatches
                      expectation
                      finalSourceStatus
                      && exactFileStatusMatches
                        openedStatus
                        finalSourceStatus
                      && exactFileStatusMatches
                        finalSourceStatus
                        finalPathStatus
                      && copiedBytes == snapshotSize expectation
                      && observedDigest == snapshotDigest expectation
                  )
                  ( ioError
                      ( userError
                          "bounded-command executable changed while the anchor snapshotted it"
                      )
                  )
                let targetMode =
                      ownerReadMode .|. ownerExecuteMode
                PosixFiles.setFdMode targetDescriptor targetMode
                fileSynchronise targetDescriptor
                _ <- fdSeek targetDescriptor AbsoluteSeek 0
                sealedContext <-
                  hashSnapshotDescriptor
                    targetDescriptor
                    (snapshotSize expectation)
                    SHA256.init
                sealedDescriptorStatus <- getFdStatus targetDescriptor
                sealedPathStatus <-
                  getSymbolicLinkStatus snapshotPath
                finalTargetStatus <- getFdStatus targetDescriptor
                let sealedDigest =
                      "sha256:"
                        <> TextEncoding.decodeUtf8
                          (Base16.encode (SHA256.finalize sealedContext))
                unless
                  ( sameFileObjectStatus
                      openedTargetStatus
                      sealedDescriptorStatus
                      && exactFileStatusMatches
                        sealedDescriptorStatus
                        sealedPathStatus
                      && exactFileStatusMatches
                        sealedPathStatus
                        finalTargetStatus
                      && PosixFiles.fileMode sealedDescriptorStatus
                        .&. PosixFiles.accessModes
                        == targetMode
                      && fromIntegral
                        (PosixFiles.fileSize sealedDescriptorStatus)
                        == snapshotSize expectation
                      && sealedDigest == snapshotDigest expectation
                  )
                  (ioError (userError "bounded-command executable snapshot did not seal"))
                synchroniseDirectory snapshotRoot
            )
            (ignoreIOException (closeFd targetDescriptor))
          pure snapshotPath
      )
      (ignoreIOException (closeFd sourceDescriptor))

artifactClosureSnapshotPair ::
  [PackageClosureSnapshotExpectation] ->
  [PackageClosureSnapshotExpectation] ->
  IO
    ( Maybe
        ( PackageClosureSnapshotExpectation,
          PackageClosureSnapshotExpectation
        )
    )
artifactClosureSnapshotPair sourceClosures sealedClosures = do
  unless
    ( length sourceClosures == length sealedClosures
        && and
          [ closureSnapshotRole source == closureSnapshotRole sealed
          | (source, sealed) <- zip sourceClosures sealedClosures
          ]
    )
    (ioError (userError "sealed package closure roles changed during materialization"))
  case [ (source, sealed)
       | (source, sealed) <- zip sourceClosures sealedClosures,
         closureSnapshotRole source == SnapshotArtifactRoot
       ] of
    [] -> pure Nothing
    [artifactSnapshot] -> pure (Just artifactSnapshot)
    _ ->
      ioError
        (userError "bounded-command artifact snapshot authority is ambiguous")

materializeArtifactSnapshotExecutable ::
  ExecutableSnapshotExpectation ->
  PackageClosureSnapshotExpectation ->
  PackageClosureSnapshotExpectation ->
  [String] ->
  Maybe FilePath ->
  IO (FilePath, [String], Maybe FilePath)
materializeArtifactSnapshotExecutable
  executableExpectation
  sourceArtifact
  sealedArtifact
  arguments
  workingDirectory = do
    let sourceRoot = closureSnapshotRoot sourceArtifact
        sealedRoot = closureSnapshotRoot sealedArtifact
    configuredRelative <-
      requireArtifactDescendant
        "configured executable"
        sourceRoot
        (snapshotConfiguredPath executableExpectation)
    canonicalRelative <-
      requireArtifactDescendant
        "canonical executable"
        sourceRoot
        (snapshotCanonicalPath executableExpectation)
    let sealedConfiguredPath = sealedRoot </> configuredRelative
        sealedCanonicalPath = sealedRoot </> canonicalRelative
    observedCanonicalPath <- canonicalizePath sealedConfiguredPath
    unless
      ( normalise observedCanonicalPath == normalise sealedCanonicalPath
          && pathWithinOwnedRoot sealedRoot observedCanonicalPath
      )
      ( ioError
          ( userError
              "sealed artifact executable canonical target escaped its copied closure"
          )
      )
    canonicalStatus <- getSymbolicLinkStatus observedCanonicalPath
    canonicalDigest <- digestSealedSnapshotFile observedCanonicalPath
    unless
      ( isRegularFile canonicalStatus
          && not (isSymbolicLink canonicalStatus)
          && fromIntegral (PosixFiles.fileSize canonicalStatus)
            == snapshotSize executableExpectation
          && canonicalDigest == snapshotDigest executableExpectation
          && PosixFiles.fileMode canonicalStatus
            .&. PosixFiles.ownerExecuteMode
            /= 0
      )
      (ioError (userError "sealed artifact executable identity disagreed"))
    rewrittenArguments <-
      mapM
        (rewriteArtifactAbsoluteOperand sourceRoot sealedRoot)
        arguments
    rewrittenWorkingDirectory <-
      case workingDirectory of
        Nothing ->
          ioError
            (userError "closed artifact command requires an owned working directory")
        Just directory ->
          Just <$> rewriteArtifactAbsoluteOperand sourceRoot sealedRoot directory
    pure
      ( sealedConfiguredPath,
        rewrittenArguments,
        rewrittenWorkingDirectory
      )

requireArtifactDescendant ::
  String ->
  FilePath ->
  FilePath ->
  IO FilePath
requireArtifactDescendant label artifactRoot path = do
  let relativePath = normalise (makeRelative artifactRoot path)
  unless
    ( isAbsolute artifactRoot
        && isAbsolute path
        && pathWithinOwnedRoot artifactRoot path
        && not (isAbsolute relativePath)
        && relativePath /= "."
        && notElem ".." (splitPathComponents relativePath)
    )
    ( ioError
        ( userError
            ( "closed artifact "
                <> label
                <> " is not a descendant of its observed root"
            )
        )
    )
  pure relativePath

rewriteArtifactAbsoluteOperand ::
  FilePath ->
  FilePath ->
  String ->
  IO String
rewriteArtifactAbsoluteOperand sourceRoot sealedRoot operand
  | '\NUL' `elem` operand =
      ioError (userError "closed artifact operand contains NUL")
  | not (isAbsolute operand) = pure operand
  | pathWithinOwnedRoot sourceRoot operand =
      pure (sealedRoot </> makeRelative sourceRoot operand)
  | otherwise =
      ioError
        ( userError
            ( "closed artifact command contains a cross-root absolute operand: "
                <> operand
            )
        )

sameFileObjectStatus :: FileStatus -> FileStatus -> Bool
sameFileObjectStatus expected observed =
  PosixFiles.deviceID expected == PosixFiles.deviceID observed
    && PosixFiles.fileID expected == PosixFiles.fileID observed

materializeRuntimeLibrarySnapshot ::
  FilePath ->
  RuntimeLibrarySnapshotExpectation ->
  IO RuntimeLibrarySnapshotExpectation
materializeRuntimeLibrarySnapshot snapshotRoot expectation =
  mask $ \restore -> do
    canonicalPath <-
      restore
        (canonicalizePath (runtimeLibrarySnapshotConfiguredPath expectation))
    unless
      ( normalise canonicalPath
          == normalise
            (runtimeLibrarySnapshotCanonicalPath expectation)
      )
      (ioError (userError "runtime library canonical target changed before snapshot"))
    let destinationDirectory =
          snapshotRoot </> "dyld-libraries"
        destinationPath =
          destinationDirectory
            </> runtimeLibrarySnapshotLeafName expectation
    createPrivateDirectoryTree snapshotRoot destinationDirectory
    sourceDescriptor <-
      openFd
        (runtimeLibrarySnapshotCanonicalPath expectation)
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( do
          openedSourceStatus <- getFdStatus sourceDescriptor
          unless
            (exactRuntimeLibraryStatusMatches expectation openedSourceStatus)
            (ioError (userError "runtime library identity changed before snapshot"))
          destinationDescriptor <-
            openFd
              destinationPath
              ReadWrite
              defaultFileFlags
                { exclusive = True,
                  nofollow = True,
                  creat = Just commandActivityLeaseMode,
                  cloexec = True
                }
          finallyPreservingPrimary
            ( restore $ do
                openedDestinationStatus <-
                  getFdStatus destinationDescriptor
                unless
                  (isRegularFile openedDestinationStatus)
                  (ioError (userError "runtime library snapshot target is not regular"))
                (copiedBytes, sourceContext) <-
                  copyExecutableDescriptor
                    sourceDescriptor
                    destinationDescriptor
                    (runtimeLibrarySnapshotSize expectation)
                    0
                    SHA256.init
                finalSourceStatus <- getFdStatus sourceDescriptor
                finalSourcePathStatus <-
                  getSymbolicLinkStatus
                    (runtimeLibrarySnapshotCanonicalPath expectation)
                let sourceDigest =
                      "sha256:"
                        <> TextEncoding.decodeUtf8
                          (Base16.encode (SHA256.finalize sourceContext))
                unless
                  ( exactRuntimeLibraryStatusMatches
                      expectation
                      finalSourceStatus
                      && exactFileStatusMatches
                        openedSourceStatus
                        finalSourceStatus
                      && exactFileStatusMatches
                        finalSourceStatus
                        finalSourcePathStatus
                      && copiedBytes
                        == runtimeLibrarySnapshotSize expectation
                      && sourceDigest
                        == runtimeLibrarySnapshotDigest expectation
                  )
                  (ioError (userError "runtime library changed while snapshotted"))
                PosixFiles.setFdMode
                  destinationDescriptor
                  ownerReadMode
                fileSynchronise destinationDescriptor
                _ <- fdSeek destinationDescriptor AbsoluteSeek 0
                destinationContext <-
                  hashSnapshotDescriptor
                    destinationDescriptor
                    (runtimeLibrarySnapshotSize expectation)
                    SHA256.init
                destinationStatus <-
                  getFdStatus destinationDescriptor
                destinationPathStatus <-
                  getSymbolicLinkStatus destinationPath
                finalDestinationStatus <-
                  getFdStatus destinationDescriptor
                let destinationDigest =
                      "sha256:"
                        <> TextEncoding.decodeUtf8
                          (Base16.encode (SHA256.finalize destinationContext))
                unless
                  ( sameFileObjectStatus
                      openedDestinationStatus
                      destinationStatus
                      && exactFileStatusMatches
                        destinationStatus
                        destinationPathStatus
                      && exactFileStatusMatches
                        destinationPathStatus
                        finalDestinationStatus
                      && PosixFiles.fileMode destinationStatus
                        .&. PosixFiles.accessModes
                        == ownerReadMode
                      && fromIntegral
                        (PosixFiles.fileSize destinationStatus)
                        == runtimeLibrarySnapshotSize expectation
                      && destinationDigest
                        == runtimeLibrarySnapshotDigest expectation
                  )
                  (ioError (userError "runtime library destination disagreed"))
                synchroniseDirectory destinationDirectory
                pure
                  expectation
                    { runtimeLibrarySnapshotConfiguredPath =
                        destinationPath,
                      runtimeLibrarySnapshotCanonicalPath =
                        destinationPath,
                      runtimeLibrarySnapshotDeviceId =
                        fromIntegral
                          (PosixFiles.deviceID destinationStatus),
                      runtimeLibrarySnapshotFileId =
                        fromIntegral
                          (PosixFiles.fileID destinationStatus),
                      runtimeLibrarySnapshotMode =
                        fromIntegral
                          (PosixFiles.fileMode destinationStatus)
                    }
            )
            (ignoreIOException (closeFd destinationDescriptor))
      )
      (ignoreIOException (closeFd sourceDescriptor))

exactRuntimeLibraryStatusMatches ::
  RuntimeLibrarySnapshotExpectation ->
  FileStatus ->
  Bool
exactRuntimeLibraryStatusMatches expectation status =
  isRegularFile status
    && not (isSymbolicLink status)
    && fromIntegral (PosixFiles.deviceID status)
      == runtimeLibrarySnapshotDeviceId expectation
    && fromIntegral (PosixFiles.fileID status)
      == runtimeLibrarySnapshotFileId expectation
    && fromIntegral (PosixFiles.fileMode status)
      == runtimeLibrarySnapshotMode expectation
    && fromIntegral (PosixFiles.fileSize status)
      == runtimeLibrarySnapshotSize expectation

materializePackageClosureSnapshot ::
  FilePath ->
  Int ->
  PackageClosureSnapshotExpectation ->
  IO PackageClosureSnapshotExpectation
materializePackageClosureSnapshot snapshotRoot closureIndex expectation = do
  let sourceRoot = closureSnapshotRoot expectation
      destinationRoot =
        case closureSnapshotRole expectation of
          SnapshotPythonHome ->
            snapshotRoot
              </> "python-framework"
              </> "Python.framework"
              </> "Versions"
              </> takeFileName sourceRoot
          SnapshotPythonPath ->
            snapshotRoot
              </> ("python-path-" <> show closureIndex)
          SnapshotProjectSource ->
            snapshotRoot
              </> ("project-source-" <> show closureIndex)
          SnapshotArtifactRoot ->
            snapshotRoot </> "artifact-root"
      destinationParent = takeDirectory destinationRoot
  createPrivateDirectoryTree snapshotRoot destinationParent
  sourceStatus <- getSymbolicLinkStatus sourceRoot
  unless
    (exactPackageClosureRootStatusMatches expectation sourceStatus)
    (ioError (userError "bounded-command package closure root identity changed"))
  sourceDescriptor <-
    openFd
      sourceRoot
      ReadOnly
      defaultFileFlags
        { nofollow = True,
          directory = True,
          cloexec = True
        }
  observed <-
    finallyPreservingPrimary
      ( do
          openedSourceStatus <- getFdStatus sourceDescriptor
          unless
            ( exactPackageClosureRootStatusMatches
                expectation
                openedSourceStatus
                && exactFileStatusMatches
                  sourceStatus
                  openedSourceStatus
            )
            (ioError (userError "bounded-command package closure root changed before descriptor open"))
          copied <-
            copyPackageClosureDirectory
              (closureSnapshotRole expectation == SnapshotPythonHome)
              sourceRoot
              sourceRoot
              sourceDescriptor
              openedSourceStatus
              destinationRoot
              "."
              0
              ( SnapshotClosureState
                  0
                  0
                  (SHA256.update SHA256.init "infernix-poetry-closure-v2\NUL")
              )
          finalDescriptorStatus <- getFdStatus sourceDescriptor
          finalPathStatus <- getSymbolicLinkStatus sourceRoot
          unless
            ( exactFileStatusMatches
                openedSourceStatus
                finalDescriptorStatus
                && exactFileStatusMatches
                  finalDescriptorStatus
                  finalPathStatus
            )
            (ioError (userError "bounded-command package closure root changed during descriptor copy"))
          pure copied
      )
      (ignoreIOException (closeFd sourceDescriptor))
  finalSourceStatus <- getSymbolicLinkStatus sourceRoot
  let observedDigest =
        "sha256:"
          <> TextEncoding.decodeUtf8
            (Base16.encode (SHA256.finalize (snapshotClosureContext observed)))
  unless
    ( exactPackageClosureRootStatusMatches
        expectation
        finalSourceStatus
        && exactFileStatusMatches sourceStatus finalSourceStatus
        && snapshotClosureBytesCopied observed
          == closureSnapshotBytes expectation
        && snapshotClosureFilesCopied observed
          == closureSnapshotFiles expectation
        && observedDigest == closureSnapshotDigest expectation
    )
    ( ioError
        (userError "bounded-command package closure changed while the anchor snapshotted it")
    )
  destinationStatus <- getSymbolicLinkStatus destinationRoot
  pure
    expectation
      { closureSnapshotRoot = destinationRoot,
        closureSnapshotDeviceId =
          fromIntegral (PosixFiles.deviceID destinationStatus),
        closureSnapshotFileId =
          fromIntegral (PosixFiles.fileID destinationStatus),
        closureSnapshotMode =
          fromIntegral (PosixFiles.fileMode destinationStatus)
      }

data SnapshotClosureState = SnapshotClosureState
  { snapshotClosureBytesCopied :: !Integer,
    snapshotClosureFilesCopied :: !Integer,
    snapshotClosureContext :: !SHA256.Ctx
  }

-- | Whether closure evidence still names the retained source tree or the
-- sealed copy inside an anchor generation. A Python-home source identity was
-- minted with host-bound launchers and the base site-packages link excluded;
-- its sealed copy has already omitted those entries and must hash everything
-- that remains so reinjection cannot be hidden by applying the exclusion a
-- second time.
data PackageClosureVerificationTarget
  = RetainedPackageClosureSource
  | SealedPackageClosureSnapshot

listDirectoryBoundedFromDescriptor ::
  Fd ->
  Integer ->
  IO [FilePath]
listDirectoryBoundedFromDescriptor directoryDescriptor maximumEntries
  | maximumEntries < 0 =
      ioError (userError "directory entry budget is already exhausted")
  | otherwise =
      mask $ \restore -> do
        descriptor <- dup directoryDescriptor
        setFdOption descriptor CloseOnExec True
        stream <-
          onExceptionPreservingPrimary
            (unsafeOpenDirStreamFd descriptor)
            (ignoreIOException (closeFd descriptor))
        finallyPreservingPrimary
          (restore (readEntries stream 0 []))
          (closeDirStream stream)
  where
    readEntries stream observed entries = do
      entry <- readDirStream stream
      if null entry
        then pure (List.sort entries)
        else
          if entry == "." || entry == ".."
            then readEntries stream observed entries
            else do
              let nextObserved = observed + 1
              unless
                (nextObserved <= maximumEntries)
                (ioError (userError "directory exceeds its fixed entry budget"))
              readEntries stream nextObserved (entry : entries)

copyPackageClosureDirectory ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  FileStatus ->
  FilePath ->
  FilePath ->
  Int ->
  SnapshotClosureState ->
  IO SnapshotClosureState
copyPackageClosureDirectory
  excludeBaseSitePackages
  sourceRoot
  sourceDirectory
  sourceDirectoryDescriptor
  listedStatus
  destinationDirectory
  relativeDirectory
  depth
  state = do
    unless
      (depth <= maximumPackageClosureSnapshotDepth)
      (ioError (userError "package closure copy exceeded its fixed depth bound"))
    unless
      (isDirectory listedStatus)
      (ioError (userError ("package closure directory is invalid: " <> sourceDirectory)))
    createDirectory destinationDirectory
    setFileMode destinationDirectory ownerModes
    synchroniseDirectory (takeDirectory destinationDirectory)
    entries <-
      listDirectoryBoundedFromDescriptor
        sourceDirectoryDescriptor
        ( maximumPackageClosureSnapshotFiles
            - snapshotClosureFilesCopied state
        )
    let directoryState =
          state
            { snapshotClosureContext =
                updateSnapshotClosureDigest
                  (snapshotClosureContext state)
                  ("D\NUL" <> relativeDirectory <> "\NUL")
            }
    observed <-
      foldM
        ( copyPackageClosureEntry
            excludeBaseSitePackages
            sourceRoot
            sourceDirectory
            sourceDirectoryDescriptor
            destinationDirectory
            relativeDirectory
            depth
        )
        directoryState
        entries
    finalStatus <- getFdStatus sourceDirectoryDescriptor
    unless
      (exactFileStatusMatches listedStatus finalStatus)
      (ioError (userError ("package closure directory changed: " <> sourceDirectory)))
    setFileMode
      destinationDirectory
      (ownerReadMode .|. ownerExecuteMode)
    synchroniseDirectory destinationDirectory
    synchroniseDirectory (takeDirectory destinationDirectory)
    pure observed

copyPackageClosureEntry ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  Int ->
  SnapshotClosureState ->
  FilePath ->
  IO SnapshotClosureState
copyPackageClosureEntry
  excludeBaseSitePackages
  sourceRoot
  sourceParent
  sourceParentDescriptor
  destinationParent
  parentRelative
  parentDepth
  state
  entry = do
    let sourcePath = sourceParent </> entry
        destinationPath = destinationParent </> entry
        relativePath =
          if parentRelative == "."
            then entry
            else parentRelative </> entry
    directoryResult <-
      try @IOException
        ( openFdAt
            (Just sourceParentDescriptor)
            entry
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        )
    case directoryResult of
      Right directoryDescriptor ->
        finallyPreservingPrimary
          ( do
              status <- getFdStatus directoryDescriptor
              unless
                (isDirectory status)
                (ioError (userError ("package closure child is not a directory: " <> sourcePath)))
              let nextEntries =
                    snapshotClosureFilesCopied state + 1
              unless
                (nextEntries <= maximumPackageClosureSnapshotFiles)
                (ioError (userError "package closure copy exceeded its fixed entry bound"))
              copied <-
                copyPackageClosureDirectory
                  excludeBaseSitePackages
                  sourceRoot
                  sourcePath
                  directoryDescriptor
                  status
                  destinationPath
                  relativePath
                  (parentDepth + 1)
                  state
                    { snapshotClosureFilesCopied = nextEntries
                    }
              finalStatus <- getFdStatus directoryDescriptor
              reopenedStatus <-
                reopenDirectoryEntryStatus
                  sourceParentDescriptor
                  entry
              unless
                ( exactFileStatusMatches status finalStatus
                    && exactFileStatusMatches
                      finalStatus
                      reopenedStatus
                )
                (ioError (userError ("package closure directory entry changed: " <> sourcePath)))
              pure copied
          )
          (ignoreIOException (closeFd directoryDescriptor))
      Left _ -> do
        fileResult <-
          try @IOException
            ( openFdAt
                (Just sourceParentDescriptor)
                entry
                ReadOnly
                defaultFileFlags
                  { nofollow = True,
                    nonBlock = True,
                    cloexec = True
                  }
            )
        case fileResult of
          Right sourceDescriptor ->
            finallyPreservingPrimary
              ( do
                  status <- getFdStatus sourceDescriptor
                  if isRegularFile status
                    then do
                      excluded <-
                        excludedPythonHomeShebangSnapshotFile
                          excludeBaseSitePackages
                          sourceRoot
                          relativePath
                          sourceDescriptor
                      if excluded
                        then do
                          recheckSnapshotPackageClosureFile
                            sourceParentDescriptor
                            entry
                            sourcePath
                            sourceDescriptor
                            status
                          pure state
                        else
                          copyPackageClosureFile
                            sourceParentDescriptor
                            entry
                            sourcePath
                            sourceDescriptor
                            destinationPath
                            relativePath
                            status
                            state
                    else
                      ioError
                        (userError ("package closure contains an unsupported opened entry: " <> sourcePath))
              )
              (ignoreIOException (closeFd sourceDescriptor))
          Left _ ->
            copyPackageClosureLink
              excludeBaseSitePackages
              sourceRoot
              sourceParentDescriptor
              sourceParent
              entry
              sourcePath
              destinationPath
              relativePath
              state

copyPackageClosureFile ::
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  FileStatus ->
  SnapshotClosureState ->
  IO SnapshotClosureState
copyPackageClosureFile
  sourceParentDescriptor
  sourceEntry
  sourcePath
  sourceDescriptor
  destinationPath
  relativePath
  listedStatus
  state =
    mask $ \restore -> do
      let nextBytes =
            snapshotClosureBytesCopied state
              + fromIntegral (PosixFiles.fileSize listedStatus)
          nextFiles = snapshotClosureFilesCopied state + 1
      unless
        ( nextBytes <= maximumPackageClosureSnapshotBytes
            && nextFiles <= maximumPackageClosureSnapshotFiles
        )
        (ioError (userError "package closure copy exceeded its fixed bound"))
      openedStatus <- getFdStatus sourceDescriptor
      unless
        (exactFileStatusMatches listedStatus openedStatus)
        (ioError (userError ("package closure file changed before descriptor use: " <> sourcePath)))
      destinationDescriptor <-
        openFd
          destinationPath
          ReadWrite
          defaultFileFlags
            { exclusive = True,
              nofollow = True,
              creat = Just commandActivityLeaseMode,
              cloexec = True
            }
      finallyPreservingPrimary
        ( restore $ do
            openedDestinationStatus <-
              getFdStatus destinationDescriptor
            unless
              (isRegularFile openedDestinationStatus)
              (ioError (userError ("package closure destination is not regular: " <> destinationPath)))
            (copiedBytes, digestContext) <-
              copyExecutableDescriptor
                sourceDescriptor
                destinationDescriptor
                (fromIntegral (PosixFiles.fileSize listedStatus))
                0
                SHA256.init
            finalSourceStatus <- getFdStatus sourceDescriptor
            finalNamedStatus <-
              reopenFileEntryStatus
                sourceParentDescriptor
                sourceEntry
            let fileDigest =
                  "sha256:"
                    <> TextEncoding.decodeUtf8
                      (Base16.encode (SHA256.finalize digestContext))
                executableFlag =
                  PosixFiles.fileMode listedStatus
                    .&. ( PosixFiles.ownerExecuteMode
                            .|. PosixFiles.groupExecuteMode
                            .|. PosixFiles.otherExecuteMode
                        )
                    /= 0
                destinationMode =
                  if executableFlag
                    then ownerReadMode .|. ownerExecuteMode
                    else ownerReadMode
            unless
              ( copiedBytes
                  == fromIntegral (PosixFiles.fileSize listedStatus)
                  && exactFileStatusMatches
                    openedStatus
                    finalSourceStatus
                  && exactFileStatusMatches
                    finalSourceStatus
                    finalNamedStatus
              )
              (ioError (userError ("package closure file changed while copying: " <> sourcePath)))
            PosixFiles.setFdMode
              destinationDescriptor
              destinationMode
            fileSynchronise destinationDescriptor
            _ <- fdSeek destinationDescriptor AbsoluteSeek 0
            destinationContext <-
              hashSnapshotDescriptor
                destinationDescriptor
                (fromIntegral (PosixFiles.fileSize listedStatus))
                SHA256.init
            destinationStatus <-
              getFdStatus destinationDescriptor
            destinationPathStatus <-
              getSymbolicLinkStatus destinationPath
            finalDestinationStatus <-
              getFdStatus destinationDescriptor
            let destinationDigest =
                  "sha256:"
                    <> TextEncoding.decodeUtf8
                      (Base16.encode (SHA256.finalize destinationContext))
            unless
              ( sameFileObjectStatus
                  openedDestinationStatus
                  destinationStatus
                  && exactFileStatusMatches
                    destinationStatus
                    destinationPathStatus
                  && exactFileStatusMatches
                    destinationPathStatus
                    finalDestinationStatus
                  && PosixFiles.fileMode destinationStatus
                    .&. PosixFiles.accessModes
                    == destinationMode
                  && destinationDigest == fileDigest
              )
              (ioError (userError ("package closure destination digest disagreed: " <> destinationPath)))
            synchroniseDirectory
              (takeDirectory destinationPath)
            pure
              SnapshotClosureState
                { snapshotClosureBytesCopied = nextBytes,
                  snapshotClosureFilesCopied = nextFiles,
                  snapshotClosureContext =
                    updateSnapshotClosureDigest
                      (snapshotClosureContext state)
                      ( (if executableFlag then "X" else "F")
                          <> "\NUL"
                          <> relativePath
                          <> "\NUL"
                          <> show (PosixFiles.fileSize listedStatus)
                          <> "\NUL"
                          <> Text.unpack fileDigest
                          <> "\NUL"
                      )
                }
        )
        (ignoreIOException (closeFd destinationDescriptor))

copyPackageClosureLink ::
  Bool ->
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  FilePath ->
  FilePath ->
  FilePath ->
  SnapshotClosureState ->
  IO SnapshotClosureState
copyPackageClosureLink
  excludeBaseSitePackages
  sourceRoot
  sourceParentDescriptor
  sourceParent
  sourceEntry
  sourcePath
  destinationPath
  relativePath
  state = do
    unless
      ( not (null sourceEntry)
          && sourceEntry `notElem` [".", ".."]
          && takeFileName sourceEntry == sourceEntry
          && '\NUL' `notElem` sourceEntry
          && sourcePath == sourceParent </> sourceEntry
      )
      ( ioError
          ( userError
              ( "package closure link entry is not a validated single leaf of its retained parent: "
                  <> sourcePath
              )
          )
      )
    parentStatus <- getFdStatus sourceParentDescriptor
    parentPathStatus <- getSymbolicLinkStatus sourceParent
    unless
      (exactFileStatusMatches parentStatus parentPathStatus)
      (ioError (userError ("package closure link parent path changed: " <> sourceParent)))
    listedStatus <- getSymbolicLinkStatus sourcePath
    unless
      (isSymbolicLink listedStatus)
      (ioError (userError ("package closure entry is neither openable nor a symlink: " <> sourcePath)))
    linkTarget <- readSymbolicLink sourcePath
    let nextBytes =
          snapshotClosureBytesCopied state
            + fromIntegral
              ( ByteString.length
                  (TextEncoding.encodeUtf8 (Text.pack linkTarget))
              )
        nextFiles = snapshotClosureFilesCopied state + 1
    finalStatus <- getSymbolicLinkStatus sourcePath
    finalTarget <- readSymbolicLink sourcePath
    finalParentStatus <- getFdStatus sourceParentDescriptor
    finalParentPathStatus <- getSymbolicLinkStatus sourceParent
    unless
      ( exactFileStatusMatches listedStatus finalStatus
          && linkTarget == finalTarget
          && exactFileStatusMatches parentStatus finalParentStatus
          && exactFileStatusMatches
            finalParentStatus
            finalParentPathStatus
      )
      (ioError (userError ("package closure link changed: " <> sourcePath)))
    if excludeBaseSitePackages
      && excludedPythonBaseSitePackagesSnapshotLink relativePath
      then pure state
      else do
        unless
          ( safeClosureLink sourceRoot sourcePath linkTarget
              && nextBytes <= maximumPackageClosureSnapshotBytes
              && nextFiles <= maximumPackageClosureSnapshotFiles
          )
          (ioError (userError ("package closure link is unsafe: " <> sourcePath)))
        createSymbolicLink linkTarget destinationPath
        synchroniseDirectory (takeDirectory destinationPath)
        pure
          SnapshotClosureState
            { snapshotClosureBytesCopied = nextBytes,
              snapshotClosureFilesCopied = nextFiles,
              snapshotClosureContext =
                updateSnapshotClosureDigest
                  (snapshotClosureContext state)
                  ( "L\NUL"
                      <> relativePath
                      <> "\NUL"
                      <> linkTarget
                      <> "\NUL"
                  )
            }

reopenDirectoryEntryStatus :: Fd -> FilePath -> IO FileStatus
reopenDirectoryEntryStatus parentDescriptor entry =
  mask $ \restore -> do
    descriptor <-
      openFdAt
        (Just parentDescriptor)
        entry
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    finallyPreservingPrimary
      (restore (getFdStatus descriptor))
      (ignoreIOException (closeFd descriptor))

reopenFileEntryStatus :: Fd -> FilePath -> IO FileStatus
reopenFileEntryStatus parentDescriptor entry =
  mask $ \restore -> do
    descriptor <-
      openFdAt
        (Just parentDescriptor)
        entry
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            nonBlock = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          status <- getFdStatus descriptor
          unless
            (isRegularFile status)
            (ioError (userError "reopened package entry is not regular"))
          pure status
      )
      (ignoreIOException (closeFd descriptor))

-- | Tie a content-derived exclusion to the same retained file object before
-- returning without copying or hashing it. No excluded branch may turn a
-- probe-time race into an unobserved closure entry.
recheckSnapshotPackageClosureFile ::
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  FileStatus ->
  IO ()
recheckSnapshotPackageClosureFile
  parentDescriptor
  entry
  path
  descriptor
  openedStatus = do
    finalStatus <- getFdStatus descriptor
    reopenedStatus <- reopenFileEntryStatus parentDescriptor entry
    unless
      ( exactFileStatusMatches openedStatus finalStatus
          && exactFileStatusMatches finalStatus reopenedStatus
      )
      (ioError (userError ("package closure excluded file changed: " <> path)))

safeClosureLink :: FilePath -> FilePath -> FilePath -> Bool
safeClosureLink sourceRoot sourcePath linkTarget =
  not (isAbsolute linkTarget)
    && '\NUL' `notElem` linkTarget
    && let resolved =
             normalise (takeDirectory sourcePath </> linkTarget)
           rootPrefix =
             normalise sourceRoot <> "/"
        in resolved == normalise sourceRoot
             || rootPrefix `List.isPrefixOf` (resolved <> "/")

excludedPythonBaseSitePackagesSnapshotLink :: FilePath -> Bool
excludedPythonBaseSitePackagesSnapshotLink relativePath =
  case splitPathComponents (normalise relativePath) of
    ["lib", pythonDirectory, "site-packages"] ->
      "python" `List.isPrefixOf` pythonDirectory
    _ -> False

packageClosureVerificationExcludesPythonHomeHostBindings ::
  PackageClosureVerificationTarget ->
  PackageClosureSnapshotRole ->
  Bool
packageClosureVerificationExcludesPythonHomeHostBindings
  verificationTarget
  role =
    case verificationTarget of
      RetainedPackageClosureSource -> role == SnapshotPythonHome
      SealedPackageClosureSnapshot -> False

packageClosureVerificationExcludesFile ::
  PackageClosureVerificationTarget ->
  PackageClosureSnapshotRole ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Bool
packageClosureVerificationExcludesFile verificationTarget role =
  packageClosureFileExcluded
    ( packageClosureVerificationExcludesPythonHomeHostBindings
        verificationTarget
        role
    )

packageClosureVerificationExcludesLink ::
  PackageClosureVerificationTarget ->
  PackageClosureSnapshotRole ->
  FilePath ->
  Bool
packageClosureVerificationExcludesLink verificationTarget role =
  packageClosureLinkExcluded
    ( packageClosureVerificationExcludesPythonHomeHostBindings
        verificationTarget
        role
    )

-- Keep this identical to provisioning's retained-source rule. Console scripts
-- below @bin@ retain the historical absolute-host-shebang exclusion. Outside
-- @bin@, only an interpreter at the exact retained root's immediate
-- @bin/python*@ path is excluded, so the generated config helper is omitted
-- without deleting importable stdlib files carrying @/usr/local/bin/python@ or
-- @/bin/sh@.
packageClosureFileExcluded ::
  Bool ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Bool
packageClosureFileExcluded
  excludePythonHomeHostBindings
  closureRoot
  relativePath
  leading =
    excludePythonHomeHostBindings
      && snapshotShebangBindsHostInstallation leading
      && ( snapshotPythonHomeBinEntry relativePath
             || snapshotShebangBindsExactPythonHome closureRoot leading
         )

packageClosureLinkExcluded :: Bool -> FilePath -> Bool
packageClosureLinkExcluded excludePythonHomeHostBindings relativePath =
  excludePythonHomeHostBindings
    && excludedPythonBaseSitePackagesSnapshotLink relativePath

excludedPythonHomeShebangSnapshotFile ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  IO Bool
excludedPythonHomeShebangSnapshotFile
  excludePythonHomeHostBindings
  closureRoot
  relativePath
  descriptor
    | not excludePythonHomeHostBindings = pure False
    | otherwise = do
        _ <- fdSeek descriptor AbsoluteSeek 0
        leading <- readRegularFdPrefix 512 descriptor
        _ <- fdSeek descriptor AbsoluteSeek 0
        pure
          ( packageClosureFileExcluded
              excludePythonHomeHostBindings
              closureRoot
              relativePath
              leading
          )

snapshotShebangBindsHostInstallation :: ByteString.ByteString -> Bool
snapshotShebangBindsHostInstallation leading =
  case snapshotShebangInterpreterPath leading of
    Just interpreterPath ->
      isAbsolute interpreterPath
        && normalise interpreterPath /= "/usr/bin/env"
    Nothing -> False

snapshotShebangInterpreterPath :: ByteString.ByteString -> Maybe FilePath
snapshotShebangInterpreterPath leading =
  case ByteString.stripPrefix (ByteString.pack [0x23, 0x21]) leading of
    Nothing -> Nothing
    Just afterMarker ->
      case ByteString8.words (ByteString8.takeWhile (/= '\n') afterMarker) of
        interpreter : _ -> Just (ByteString8.unpack interpreter)
        [] -> Nothing

snapshotPythonHomeBinEntry :: FilePath -> Bool
snapshotPythonHomeBinEntry relativePath =
  case splitPathComponents (normalise relativePath) of
    "bin" : _ -> True
    _ -> False

snapshotShebangBindsExactPythonHome ::
  FilePath ->
  ByteString.ByteString ->
  Bool
snapshotShebangBindsExactPythonHome closureRoot leading =
  case snapshotShebangInterpreterPath leading of
    Just interpreterPath ->
      isAbsolute interpreterPath
        && '\NUL' `notElem` interpreterPath
        && normalise interpreterPath == interpreterPath
        && normalise (takeDirectory interpreterPath)
          == normalise (closureRoot </> "bin")
        && "python" `List.isPrefixOf` takeFileName interpreterPath
    Nothing -> False

splitPathComponents :: FilePath -> [FilePath]
splitPathComponents path =
  filter
    (\component -> component /= "/" && component /= ".")
    (splitDirectories path)

createPrivateDirectoryTree :: FilePath -> FilePath -> IO ()
createPrivateDirectoryTree ownedRoot destination
  | normalise destination == normalise ownedRoot = pure ()
  | otherwise = do
      let parent = takeDirectory destination
      createPrivateDirectoryTree ownedRoot parent
      result <-
        try @IOException (createDirectory destination)
      case result of
        Right () -> do
          setFileMode destination ownerModes
          synchroniseDirectory parent
        Left failure
          | isAlreadyExistsError failure -> do
              status <- getSymbolicLinkStatus destination
              unless
                (isDirectory status && not (isSymbolicLink status))
                (ioError (userError ("snapshot parent is not a real directory: " <> destination)))
          | otherwise -> ioError failure

sealedExecutableSnapshotExpectation ::
  FilePath ->
  ExecutableSnapshotExpectation ->
  [PackageClosureSnapshotExpectation] ->
  [RuntimeLibrarySnapshotExpectation] ->
  IO ExecutableSnapshotExpectation
sealedExecutableSnapshotExpectation
  snapshotPath
  sourceExpectation
  packageClosures
  runtimeLibraries = do
    canonicalPath <- canonicalizePath snapshotPath
    unless
      ( all
          ( \closure ->
              closureSnapshotRole closure /= SnapshotArtifactRoot
                || pathWithinOwnedRoot
                  (closureSnapshotRoot closure)
                  canonicalPath
          )
          packageClosures
      )
      (ioError (userError "sealed executable canonical target escaped its artifact closure"))
    status <- getSymbolicLinkStatus canonicalPath
    digest <- digestSealedSnapshotFile canonicalPath
    unless
      ( isRegularFile status
          && not (isSymbolicLink status)
          && fromIntegral (PosixFiles.fileSize status)
            == snapshotSize sourceExpectation
          && digest == snapshotDigest sourceExpectation
      )
      (ioError (userError "sealed executable snapshot identity disagreed"))
    pure
      ExecutableSnapshotExpectation
        { snapshotConfiguredPath = snapshotPath,
          snapshotCanonicalPath = canonicalPath,
          snapshotDeviceId = fromIntegral (PosixFiles.deviceID status),
          snapshotFileId = fromIntegral (PosixFiles.fileID status),
          snapshotMode = fromIntegral (PosixFiles.fileMode status),
          snapshotSize = fromIntegral (PosixFiles.fileSize status),
          snapshotDigest = digest,
          snapshotPackageClosures = packageClosures,
          snapshotRuntimeLibraries = runtimeLibraries,
          snapshotTestHook = Nothing
        }

digestSealedSnapshotFile :: FilePath -> IO Text.Text
digestSealedSnapshotFile path =
  mask $ \restore -> do
    listedStatus <- getSymbolicLinkStatus path
    descriptor <-
      openFd
        path
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          openedStatus <- getFdStatus descriptor
          unless
            ( isRegularFile openedStatus
                && not (isSymbolicLink openedStatus)
                && exactFileStatusMatches listedStatus openedStatus
            )
            (ioError (userError ("sealed snapshot file changed before open: " <> path)))
          context <-
            hashSnapshotDescriptor
              descriptor
              (fromIntegral (PosixFiles.fileSize openedStatus))
              SHA256.init
          finalStatus <- getFdStatus descriptor
          finalPathStatus <- getSymbolicLinkStatus path
          unless
            ( exactFileStatusMatches openedStatus finalStatus
                && exactFileStatusMatches finalStatus finalPathStatus
            )
            (ioError (userError ("sealed snapshot file changed while hashing: " <> path)))
          pure
            ( "sha256:"
                <> TextEncoding.decodeUtf8
                  (Base16.encode (SHA256.finalize context))
            )
      )
      (ignoreIOException (closeFd descriptor))

hashSnapshotDescriptor ::
  Fd ->
  Integer ->
  SHA256.Ctx ->
  IO SHA256.Ctx
hashSnapshotDescriptor descriptor expectedBytes =
  go 0
  where
    go observedBytes context
      | observedBytes > expectedBytes =
          ioError (userError "snapshot descriptor exceeded its exact byte bound")
      | otherwise = do
          let remaining = expectedBytes - observedBytes
              requestBytes =
                fromIntegral (min (64 * 1024) (remaining + 1))
          chunk <- readRegularFdChunk descriptor requestBytes
          if ByteString.null chunk
            then do
              unless
                (observedBytes == expectedBytes)
                (ioError (userError "snapshot descriptor ended before its exact byte bound"))
              pure context
            else do
              let nextBytes =
                    observedBytes
                      + fromIntegral (ByteString.length chunk)
                  nextContext = SHA256.update context chunk
              unless
                (nextBytes <= expectedBytes)
                (ioError (userError "snapshot descriptor grew beyond its exact byte bound"))
              nextContext `seq` go nextBytes nextContext

updateSnapshotClosureDigest :: SHA256.Ctx -> String -> SHA256.Ctx
updateSnapshotClosureDigest context =
  SHA256.update context . TextEncoding.encodeUtf8 . Text.pack

exactPackageClosureRootStatusMatches ::
  PackageClosureSnapshotExpectation ->
  FileStatus ->
  Bool
exactPackageClosureRootStatusMatches expectation status =
  isDirectory status
    && not (isSymbolicLink status)
    && fromIntegral (PosixFiles.deviceID status)
      == closureSnapshotDeviceId expectation
    && fromIntegral (PosixFiles.fileID status)
      == closureSnapshotFileId expectation
    && fromIntegral (PosixFiles.fileMode status)
      == closureSnapshotMode expectation

data PythonClosurePlatform
  = PythonClosureLinux
  | PythonClosureNonLinux

renderPythonPackageClosureSnapshotEnvironment ::
  PythonClosurePlatform ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  [FilePath] ->
  Bool ->
  [(String, String)]
renderPythonPackageClosureSnapshotEnvironment
  platform
  snapshotRoot
  pythonHome
  pythonPaths
  projectSources
  hasRuntimeLibraries =
    [ ("PYTHONHOME", pythonHome),
      ( "PYTHONPATH",
        List.intercalate ":" (pythonPaths <> projectSources)
      )
    ]
      <> case platform of
        PythonClosureLinux -> []
        PythonClosureNonLinux ->
          ("DYLD_FRAMEWORK_PATH", snapshotRoot </> "python-framework")
            : [ ( "DYLD_LIBRARY_PATH",
                  snapshotRoot </> "dyld-libraries"
                )
              | hasRuntimeLibraries
              ]

packageClosureSnapshotEnvironment ::
  FilePath ->
  ExecutableSnapshotExpectation ->
  [PackageClosureSnapshotExpectation] ->
  [RuntimeLibrarySnapshotExpectation] ->
  IO [(String, String)]
packageClosureSnapshotEnvironment
  snapshotRoot
  executableExpectation
  closures
  runtimeLibraries =
    case ( [ closureSnapshotRoot closure
           | closure <- closures,
             closureSnapshotRole closure == SnapshotPythonHome
           ],
           [ closureSnapshotRoot closure
           | closure <- closures,
             closureSnapshotRole closure == SnapshotPythonPath
           ],
           [ closureSnapshotRoot closure
           | closure <- closures,
             closureSnapshotRole closure == SnapshotProjectSource
           ],
           [ closureSnapshotRoot closure
           | closure <- closures,
             closureSnapshotRole closure == SnapshotArtifactRoot
           ]
         ) of
      ([], [], [], [])
        | null runtimeLibraries -> pure []
      ([pythonHome], pythonPaths@(_ : _), projectSources, []) ->
        pure
          ( renderPythonPackageClosureSnapshotEnvironment
              ( if SystemInfo.os == "linux"
                  then PythonClosureLinux
                  else PythonClosureNonLinux
              )
              snapshotRoot
              pythonHome
              pythonPaths
              projectSources
              (not (null runtimeLibraries))
          )
      ([], [], [], [artifactRoot])
        | null runtimeLibraries ->
            artifactSnapshotEnvironment
              artifactRoot
              (snapshotConfiguredPath executableExpectation)
      _ ->
        ioError
          (userError "sealed package closure roles are incomplete or ambiguous")

artifactSnapshotEnvironment ::
  FilePath ->
  FilePath ->
  IO [(String, String)]
artifactSnapshotEnvironment artifactRoot executablePath = do
  relativeExecutable <-
    requireArtifactDescendant
      "sealed executable"
      artifactRoot
      executablePath
  pure (artifactSnapshotRuntimeEnvironment artifactRoot relativeExecutable)

-- | The fixed runtime environment each sealed artifact target requires,
-- selected by that target's exact relative position inside its generation.
artifactSnapshotRuntimeEnvironment ::
  FilePath ->
  FilePath ->
  [(String, String)]
artifactSnapshotRuntimeEnvironment artifactRoot relativeExecutable =
  case splitPathComponents relativeExecutable of
    ["native", "bin", executableLeaf]
      | executableLeaf `elem` ["llama-cli", "whisper-cli"] ->
          [ ( "DYLD_FRAMEWORK_PATH",
              artifactRoot </> "native" </> "frameworks"
            ),
            ( "DYLD_LIBRARY_PATH",
              List.intercalate
                ":"
                [ artifactRoot </> "native" </> "lib",
                  artifactRoot </> "native" </> "libexec"
                ]
            ),
            ( "GGML_BACKEND_PATH",
              artifactRoot </> "native" </> "libexec"
            ),
            ("DYLD_PRINT_LIBRARIES", "1")
          ]
    relativeComponents
      | relativeComponents
          == splitPathComponents
            Provisioning.fixedVenvPythonRelativePath ->
          [ ("PYTHONHOME", artifactRoot </> "python-home")
          ]
            <> take
              2
              (Provisioning.installedPythonDyldRuntimeEnvironment artifactRoot)
            <> [("PYTHONNOUSERSITE", "1")]
            <> drop
              2
              (Provisioning.installedPythonDyldRuntimeEnvironment artifactRoot)
    relativeComponents
      | relativeComponents
          == splitPathComponents
            ( Provisioning.installedSmokeExecutableRelativePath
                Provisioning.JvmAdapter
            ) ->
          [("DYLD_PRINT_LIBRARIES", "1")]
    _ -> []

installedPythonSourceIsolationRuntimeEnvironment ::
  FilePath ->
  FilePath ->
  [(String, String)]
installedPythonSourceIsolationRuntimeEnvironment artifactRoot relativeExecutable =
  filter
    (not . List.isPrefixOf "DYLD_" . fst)
    (artifactSnapshotRuntimeEnvironment artifactRoot relativeExecutable)

validateTargetExecutableSnapshot :: SupervisorPlan -> IO ()
validateTargetExecutableSnapshot plan =
  case supervisorPlanExecutableSnapshot plan of
    Nothing -> pure ()
    Just expectation -> do
      let executablePath = supervisorPlanExecutable plan
          snapshotRoot = supervisorPlanExecutableSnapshotRoot plan
      unless
        ( validPackageClosureSnapshotAggregate
            (snapshotPackageClosures expectation)
            && validRuntimeLibrarySnapshotAggregate
              (snapshotRuntimeLibraries expectation)
        )
        (ioError (userError "sealed package/runtime closure aggregate is invalid"))
      canonicalPath <- canonicalizePath executablePath
      -- An operating-system platform binary is executed in place rather than
      -- from the anchor snapshot, because a copy of one carries no usable
      -- signature and is killed at exec. Its exact identity is still required
      -- to match the recorded expectation; only the snapshot-containment
      -- requirement is lifted, and only for paths the OS itself protects.
      unless
        ( normalise canonicalPath
            == normalise (snapshotCanonicalPath expectation)
            && ( ( normalise executablePath
                     == normalise (snapshotConfiguredPath expectation)
                     && pathWithinOwnedRoot snapshotRoot executablePath
                 )
                   || systemPlatformBinaryPath canonicalPath
               )
        )
        (ioError (userError "sealed target executable escaped its anchor snapshot"))
      status <- getSymbolicLinkStatus canonicalPath
      digest <- digestSealedSnapshotFile canonicalPath
      unless
        ( exactExecutableStatusMatches expectation status
            && digest == snapshotDigest expectation
        )
        (ioError (userError "sealed target executable identity disagreed"))
      mapM_
        (verifySealedPackageClosure snapshotRoot)
        (snapshotPackageClosures expectation)
      mapM_
        ( if SystemInfo.os == "linux"
            then verifyRetainedRuntimeLibrary
            else verifySealedRuntimeLibrary snapshotRoot
        )
        (snapshotRuntimeLibraries expectation)
      validateSealedArtifactOperands plan expectation
      expectedEnvironment <-
        packageClosureSnapshotEnvironment
          snapshotRoot
          expectation
          (snapshotPackageClosures expectation)
          (snapshotRuntimeLibraries expectation)
      either
        (ioError . userError)
        pure
        ( validateSealedTargetClosureEnvironment
            expectedEnvironment
            (supervisorPlanEnvironment plan)
        )

validateSealedTargetClosureEnvironment ::
  [(String, String)] ->
  [(String, String)] ->
  Either String ()
validateSealedTargetClosureEnvironment expectedEnvironment environment =
  mapM_
    ( \(name, value) ->
        unless
          (lookup name environment == Just value)
          ( Left
              ( "sealed target closure environment disagreed for "
                  <> name
                  <> "; expected="
                  <> show value
                  <> "; observed="
                  <> show (lookup name environment)
              )
          )
    )
    expectedEnvironment

validateSealedArtifactOperands ::
  SupervisorPlan ->
  ExecutableSnapshotExpectation ->
  IO ()
validateSealedArtifactOperands plan expectation =
  case [ closureSnapshotRoot closure
       | closure <- snapshotPackageClosures expectation,
         closureSnapshotRole closure == SnapshotArtifactRoot
       ] of
    [] -> pure ()
    [artifactRoot] -> do
      unless
        ( pathWithinOwnedRoot
            artifactRoot
            (supervisorPlanExecutable plan)
        )
        (ioError (userError "sealed artifact executable escaped its copied root"))
      mapM_
        ( \argument ->
            when
              ( isAbsolute argument
                  && not (pathWithinOwnedRoot artifactRoot argument)
              )
              ( ioError
                  ( userError
                      "sealed artifact command contains a cross-root absolute argument"
                  )
              )
        )
        (supervisorPlanArguments plan)
      case supervisorPlanWorkingDirectory plan of
        Just workingDirectory
          | normalise workingDirectory == normalise artifactRoot ->
              pure ()
        _ ->
          ioError
            (userError "sealed artifact command working directory is not its copied root")
    _ ->
      ioError
        (userError "sealed artifact command has ambiguous copied roots")

verifySealedRuntimeLibrary ::
  FilePath ->
  RuntimeLibrarySnapshotExpectation ->
  IO ()
verifySealedRuntimeLibrary snapshotRoot expectation = do
  let path = runtimeLibrarySnapshotConfiguredPath expectation
  unless
    ( pathWithinOwnedRoot snapshotRoot path
        && normalise path
          == normalise
            (runtimeLibrarySnapshotCanonicalPath expectation)
    )
    (ioError (userError "sealed runtime library escaped its anchor snapshot"))
  canonicalPath <- canonicalizePath path
  unless
    (normalise canonicalPath == normalise path)
    (ioError (userError "sealed runtime library canonical path disagreed"))
  status <- getSymbolicLinkStatus path
  digest <- digestSealedSnapshotFile path
  unless
    ( exactRuntimeLibraryStatusMatches expectation status
        && digest == runtimeLibrarySnapshotDigest expectation
    )
    (ioError (userError "sealed runtime library identity disagreed"))

verifyRetainedRuntimeLibrary ::
  RuntimeLibrarySnapshotExpectation ->
  IO ()
verifyRetainedRuntimeLibrary expectation = do
  let configuredPath =
        runtimeLibrarySnapshotConfiguredPath expectation
      canonicalExpectation =
        runtimeLibrarySnapshotCanonicalPath expectation
  canonicalPath <- canonicalizePath configuredPath
  unless
    (normalise canonicalPath == normalise canonicalExpectation)
    (ioError (userError "retained runtime library canonical path disagreed"))
  status <- getSymbolicLinkStatus canonicalPath
  digest <- digestSealedSnapshotFile canonicalPath
  unless
    ( exactRuntimeLibraryStatusMatches expectation status
        && digest == runtimeLibrarySnapshotDigest expectation
    )
    (ioError (userError "retained runtime library identity disagreed"))

verifySealedPackageClosure ::
  FilePath ->
  PackageClosureSnapshotExpectation ->
  IO ()
verifySealedPackageClosure snapshotRoot expectation = do
  let closureRoot = closureSnapshotRoot expectation
  unless
    (pathWithinOwnedRoot snapshotRoot closureRoot)
    (ioError (userError "sealed package closure escaped its anchor snapshot"))
  verifyPackageClosure
    SealedPackageClosureSnapshot
    expectation

verifyRetainedPackageClosure ::
  PackageClosureSnapshotExpectation ->
  IO ()
verifyRetainedPackageClosure =
  verifyPackageClosure RetainedPackageClosureSource

verifyPackageClosure ::
  PackageClosureVerificationTarget ->
  PackageClosureSnapshotExpectation ->
  IO ()
verifyPackageClosure verificationTarget expectation = do
  let closureRoot = closureSnapshotRoot expectation
      excludePythonHomeHostBindings =
        packageClosureVerificationExcludesPythonHomeHostBindings
          verificationTarget
          (closureSnapshotRole expectation)
  rootStatus <- getSymbolicLinkStatus closureRoot
  unless
    (exactPackageClosureRootStatusMatches expectation rootStatus)
    (ioError (userError "sealed package closure root identity disagreed"))
  rootDescriptor <-
    openFd
      closureRoot
      ReadOnly
      defaultFileFlags
        { nofollow = True,
          directory = True,
          cloexec = True
        }
  observed <-
    finallyPreservingPrimary
      ( do
          openedStatus <- getFdStatus rootDescriptor
          unless
            ( exactPackageClosureRootStatusMatches expectation openedStatus
                && exactFileStatusMatches rootStatus openedStatus
            )
            (ioError (userError "sealed package closure root changed before descriptor verification"))
          result <-
            digestSealedPackageClosureDirectory
              excludePythonHomeHostBindings
              closureRoot
              closureRoot
              rootDescriptor
              openedStatus
              "."
              0
              ( SnapshotClosureState
                  0
                  0
                  (SHA256.update SHA256.init "infernix-poetry-closure-v2\NUL")
              )
          finalDescriptorStatus <- getFdStatus rootDescriptor
          finalPathStatus <- getSymbolicLinkStatus closureRoot
          unless
            ( exactFileStatusMatches
                openedStatus
                finalDescriptorStatus
                && exactFileStatusMatches
                  finalDescriptorStatus
                  finalPathStatus
            )
            (ioError (userError "sealed package closure root changed during descriptor verification"))
          pure result
      )
      (ignoreIOException (closeFd rootDescriptor))
  finalRootStatus <- getSymbolicLinkStatus closureRoot
  let rootIdentityMatches =
        exactPackageClosureRootStatusMatches
          expectation
          finalRootStatus
      rootStableAfterClose =
        exactFileStatusMatches rootStatus finalRootStatus
      observedBytes = snapshotClosureBytesCopied observed
      observedFiles = snapshotClosureFilesCopied observed
      observedDigest =
        "sha256:"
          <> TextEncoding.decodeUtf8
            (Base16.encode (SHA256.finalize (snapshotClosureContext observed)))
  unless
    ( rootIdentityMatches
        && rootStableAfterClose
        && observedBytes == closureSnapshotBytes expectation
        && observedFiles == closureSnapshotFiles expectation
        && observedDigest == closureSnapshotDigest expectation
    )
    ( ioError
        ( userError
            ( renderSealedPackageClosureContentDisagreement
                expectation
                rootIdentityMatches
                rootStableAfterClose
                observedBytes
                observedFiles
                observedDigest
            )
        )
    )

renderSealedPackageClosureContentDisagreement ::
  PackageClosureSnapshotExpectation ->
  Bool ->
  Bool ->
  Integer ->
  Integer ->
  Text.Text ->
  String
renderSealedPackageClosureContentDisagreement
  expectation
  rootIdentityMatches
  rootStableAfterClose
  observedBytes
  observedFiles
  observedDigest =
    "sealed package closure content disagreed"
      <> "; role="
      <> show (closureSnapshotRole expectation)
      <> "; root="
      <> show (closureSnapshotRoot expectation)
      <> "; rootIdentityMatches="
      <> show rootIdentityMatches
      <> "; rootStableAfterClose="
      <> show rootStableAfterClose
      <> "; expectedBytes="
      <> show (closureSnapshotBytes expectation)
      <> "; observedBytes="
      <> show observedBytes
      <> "; expectedFiles="
      <> show (closureSnapshotFiles expectation)
      <> "; observedFiles="
      <> show observedFiles
      <> "; expectedDigest="
      <> Text.unpack (closureSnapshotDigest expectation)
      <> "; observedDigest="
      <> Text.unpack observedDigest

digestSealedPackageClosureDirectory ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  FileStatus ->
  FilePath ->
  Int ->
  SnapshotClosureState ->
  IO SnapshotClosureState
digestSealedPackageClosureDirectory
  excludePythonHomeHostBindings
  closureRoot
  directoryPath
  directoryDescriptor
  listedStatus
  relativeDirectory
  depth
  state = do
    unless
      (depth <= maximumPackageClosureSnapshotDepth)
      (ioError (userError "sealed package closure exceeds its fixed depth bound"))
    unless
      (isDirectory listedStatus)
      (ioError (userError ("sealed package directory is invalid: " <> directoryPath)))
    entries <-
      listDirectoryBoundedFromDescriptor
        directoryDescriptor
        ( maximumPackageClosureSnapshotFiles
            - snapshotClosureFilesCopied state
        )
    let directoryState =
          state
            { snapshotClosureContext =
                updateSnapshotClosureDigest
                  (snapshotClosureContext state)
                  ("D\NUL" <> relativeDirectory <> "\NUL")
            }
    observed <-
      foldM
        ( digestSealedPackageClosureEntry
            excludePythonHomeHostBindings
            closureRoot
            directoryPath
            directoryDescriptor
            relativeDirectory
            depth
        )
        directoryState
        entries
    finalStatus <- getFdStatus directoryDescriptor
    unless
      (exactFileStatusMatches listedStatus finalStatus)
      (ioError (userError ("sealed package directory changed: " <> directoryPath)))
    pure observed

digestSealedPackageClosureEntry ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  Int ->
  SnapshotClosureState ->
  FilePath ->
  IO SnapshotClosureState
digestSealedPackageClosureEntry
  excludePythonHomeHostBindings
  closureRoot
  parentPath
  parentDescriptor
  parentRelative
  parentDepth
  state
  entry = do
    let path = parentPath </> entry
        relativePath =
          if parentRelative == "."
            then entry
            else parentRelative </> entry
    directoryResult <-
      try @IOException
        ( openFdAt
            (Just parentDescriptor)
            entry
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        )
    case directoryResult of
      Right directoryDescriptor ->
        finallyPreservingPrimary
          ( do
              status <- getFdStatus directoryDescriptor
              unless
                (isDirectory status)
                (ioError (userError ("sealed package child is not a directory: " <> path)))
              let nextEntries =
                    snapshotClosureFilesCopied state + 1
              unless
                (nextEntries <= maximumPackageClosureSnapshotFiles)
                (ioError (userError "sealed package closure exceeds its fixed entry bound"))
              observed <-
                digestSealedPackageClosureDirectory
                  excludePythonHomeHostBindings
                  closureRoot
                  path
                  directoryDescriptor
                  status
                  relativePath
                  (parentDepth + 1)
                  state
                    { snapshotClosureFilesCopied = nextEntries
                    }
              finalStatus <- getFdStatus directoryDescriptor
              reopenedStatus <-
                reopenDirectoryEntryStatus parentDescriptor entry
              unless
                ( exactFileStatusMatches status finalStatus
                    && exactFileStatusMatches
                      finalStatus
                      reopenedStatus
                )
                (ioError (userError ("sealed package directory entry changed: " <> path)))
              pure observed
          )
          (ignoreIOException (closeFd directoryDescriptor))
      Left _ -> do
        fileResult <-
          try @IOException
            ( openFdAt
                (Just parentDescriptor)
                entry
                ReadOnly
                defaultFileFlags
                  { nofollow = True,
                    nonBlock = True,
                    cloexec = True
                  }
            )
        case fileResult of
          Right descriptor ->
            finallyPreservingPrimary
              ( do
                  status <- getFdStatus descriptor
                  unless
                    (isRegularFile status)
                    (ioError (userError ("sealed package entry is unsupported: " <> path)))
                  excluded <-
                    excludedPythonHomeShebangSnapshotFile
                      excludePythonHomeHostBindings
                      closureRoot
                      relativePath
                      descriptor
                  if excluded
                    then do
                      recheckSnapshotPackageClosureFile
                        parentDescriptor
                        entry
                        path
                        descriptor
                        status
                      pure state
                    else
                      digestSealedPackageClosureFile
                        parentDescriptor
                        entry
                        path
                        descriptor
                        relativePath
                        status
                        state
              )
              (ignoreIOException (closeFd descriptor))
          Left _ ->
            digestSealedPackageClosureLink
              excludePythonHomeHostBindings
              closureRoot
              parentDescriptor
              parentPath
              path
              relativePath
              state

digestSealedPackageClosureFile ::
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  FileStatus ->
  SnapshotClosureState ->
  IO SnapshotClosureState
digestSealedPackageClosureFile
  parentDescriptor
  entry
  path
  descriptor
  relativePath
  status
  state = do
    let nextBytes =
          snapshotClosureBytesCopied state
            + fromIntegral (PosixFiles.fileSize status)
        nextFiles =
          snapshotClosureFilesCopied state + 1
        executableFlag =
          PosixFiles.fileMode status
            .&. ( PosixFiles.ownerExecuteMode
                    .|. PosixFiles.groupExecuteMode
                    .|. PosixFiles.otherExecuteMode
                )
            /= 0
    unless
      ( nextBytes <= maximumPackageClosureSnapshotBytes
          && nextFiles <= maximumPackageClosureSnapshotFiles
      )
      (ioError (userError "sealed package closure exceeds its fixed bound"))
    context <-
      hashSnapshotDescriptor
        descriptor
        (fromIntegral (PosixFiles.fileSize status))
        SHA256.init
    finalStatus <- getFdStatus descriptor
    reopenedStatus <-
      reopenFileEntryStatus parentDescriptor entry
    unless
      ( exactFileStatusMatches status finalStatus
          && exactFileStatusMatches finalStatus reopenedStatus
      )
      (ioError (userError ("sealed package file changed: " <> path)))
    let digest =
          "sha256:"
            <> TextEncoding.decodeUtf8
              (Base16.encode (SHA256.finalize context))
    pure
      SnapshotClosureState
        { snapshotClosureBytesCopied = nextBytes,
          snapshotClosureFilesCopied = nextFiles,
          snapshotClosureContext =
            updateSnapshotClosureDigest
              (snapshotClosureContext state)
              ( (if executableFlag then "X" else "F")
                  <> "\NUL"
                  <> relativePath
                  <> "\NUL"
                  <> show (PosixFiles.fileSize status)
                  <> "\NUL"
                  <> Text.unpack digest
                  <> "\NUL"
              )
        }

digestSealedPackageClosureLink ::
  Bool ->
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  FilePath ->
  SnapshotClosureState ->
  IO SnapshotClosureState
digestSealedPackageClosureLink
  excludePythonHomeHostBindings
  closureRoot
  parentDescriptor
  parentPath
  path
  relativePath
  state = do
    parentStatus <- getFdStatus parentDescriptor
    parentPathStatus <- getSymbolicLinkStatus parentPath
    unless
      (exactFileStatusMatches parentStatus parentPathStatus)
      (ioError (userError ("sealed package link parent changed: " <> parentPath)))
    status <- getSymbolicLinkStatus path
    unless
      (isSymbolicLink status)
      (ioError (userError ("sealed package entry is neither openable nor a symlink: " <> path)))
    linkTarget <- readSymbolicLink path
    let nextBytes =
          snapshotClosureBytesCopied state
            + fromIntegral
              ( ByteString.length
                  (TextEncoding.encodeUtf8 (Text.pack linkTarget))
              )
        nextFiles = snapshotClosureFilesCopied state + 1
    finalStatus <- getSymbolicLinkStatus path
    finalTarget <- readSymbolicLink path
    finalParentStatus <- getFdStatus parentDescriptor
    finalParentPathStatus <- getSymbolicLinkStatus parentPath
    unless
      ( exactFileStatusMatches status finalStatus
          && linkTarget == finalTarget
          && exactFileStatusMatches parentStatus finalParentStatus
          && exactFileStatusMatches
            finalParentStatus
            finalParentPathStatus
      )
      (ioError (userError ("sealed package closure link changed: " <> path)))
    if packageClosureLinkExcluded
      excludePythonHomeHostBindings
      relativePath
      then pure state
      else do
        unless
          ( safeClosureLink closureRoot path linkTarget
              && nextBytes <= maximumPackageClosureSnapshotBytes
              && nextFiles <= maximumPackageClosureSnapshotFiles
          )
          (ioError (userError ("sealed package closure link is unsafe: " <> path)))
        pure
          SnapshotClosureState
            { snapshotClosureBytesCopied = nextBytes,
              snapshotClosureFilesCopied = nextFiles,
              snapshotClosureContext =
                updateSnapshotClosureDigest
                  (snapshotClosureContext state)
                  ( "L\NUL"
                      <> relativePath
                      <> "\NUL"
                      <> linkTarget
                      <> "\NUL"
                  )
            }

-- | Whether a loaded path lies inside an owned root.
--
-- The trailing separator has to be dropped, not merely normalised. An installed
-- target's closure root is the relative @.@, and @normalise@ turns
-- @\/generation\/.@ into @\/generation\/@ rather than @\/generation@ — which
-- then fails the prefix test for every path underneath it, silently reporting
-- that a sealed run loaded nothing from its own generation.
pathWithinOwnedRoot :: FilePath -> FilePath -> Bool
pathWithinOwnedRoot ownedRoot path =
  let normalRoot = dropTrailingPathSeparator (normalise ownedRoot)
      normalPath = dropTrailingPathSeparator (normalise path)
   in normalPath == normalRoot
        || (normalRoot <> "/") `List.isPrefixOf` (normalPath <> "/")

copyExecutableDescriptor ::
  Fd ->
  Fd ->
  Integer ->
  Integer ->
  SHA256.Ctx ->
  IO (Integer, SHA256.Ctx)
copyExecutableDescriptor
  sourceDescriptor
  targetDescriptor
  expectedBytes =
    go
    where
      go copiedBytes digestContext
        | copiedBytes > expectedBytes =
            ioError (userError "snapshot source exceeded its exact byte bound")
        | otherwise = do
            let remaining = expectedBytes - copiedBytes
                requestBytes =
                  fromIntegral (min (64 * 1024) (remaining + 1))
            chunk <-
              readRegularFdChunk
                sourceDescriptor
                requestBytes
            if ByteString.null chunk
              then do
                unless
                  (copiedBytes == expectedBytes)
                  (ioError (userError "snapshot source ended before its exact byte bound"))
                pure (copiedBytes, digestContext)
              else do
                let nextBytes =
                      copiedBytes
                        + fromIntegral (ByteString.length chunk)
                unless
                  (nextBytes <= expectedBytes)
                  (ioError (userError "snapshot source grew beyond its exact byte bound"))
                writeFdFullyBlocking targetDescriptor chunk
                let nextContext = SHA256.update digestContext chunk
                nextContext `seq` go nextBytes nextContext

exactExecutableStatusMatches ::
  ExecutableSnapshotExpectation ->
  FileStatus ->
  Bool
exactExecutableStatusMatches expectation status =
  isRegularFile status
    && not (isSymbolicLink status)
    && fromIntegral (PosixFiles.deviceID status)
      == snapshotDeviceId expectation
    && fromIntegral (PosixFiles.fileID status)
      == snapshotFileId expectation
    && fromIntegral (PosixFiles.fileMode status)
      == snapshotMode expectation
    && fromIntegral (PosixFiles.fileSize status)
      == snapshotSize expectation

exactFileStatusMatches :: FileStatus -> FileStatus -> Bool
exactFileStatusMatches expected observed =
  PosixFiles.deviceID expected == PosixFiles.deviceID observed
    && PosixFiles.fileID expected == PosixFiles.fileID observed
    && PosixFiles.fileMode expected == PosixFiles.fileMode observed
    && PosixFiles.fileSize expected == PosixFiles.fileSize observed
    && PosixFiles.modificationTimeHiRes expected
      == PosixFiles.modificationTimeHiRes observed
    && PosixFiles.statusChangeTimeHiRes expected
      == PosixFiles.statusChangeTimeHiRes observed

runAnchorPrePublicationDeathHook ::
  SupervisorPlan ->
  SpawnedHelper ->
  ProvisionalProcessIdentity ->
  IO ()
runAnchorPrePublicationDeathHook plan supervisor provisionalSupervisor =
  case supervisorPlanAnchorPrePublicationDeathPath plan of
    Nothing -> pure ()
    Just readyPath -> do
      let trackedSupervisor = spawnedHelperTracked supervisor
          supervisorProcessId = trackedHelperProcessId trackedSupervisor
          trackedSupervisorIdentity =
            trackedHelperIdentity trackedSupervisor
      signalProcess sigSTOP supervisorProcessId
      stoppedStatus <-
        getProcessStatus True True supervisorProcessId
      unless (stoppedStatus == Just (Stopped sigSTOP)) $
        ioError
          (userError "bounded-command hidden supervisor did not stop before anchor death")
      validateObservedGroupMember
        "hidden stopped supervisor"
        trackedSupervisorIdentity
      unless
        ( provisionalProcessGroup provisionalSupervisor
            == activityProcessGroup trackedSupervisorIdentity
        )
        ( ioError
            ( userError
                "bounded-command hidden supervisor provisional group disagreed with its tracked helper group"
            )
        )
      ByteString8.writeFile
        readyPath
        ( ByteString8.pack
            ( show (provisionalProcessId provisionalSupervisor)
                <> "\n"
                <> show (provisionalProcessGroup provisionalSupervisor)
                <> "\n"
                <> renderProcessBirthIdentity
                  (provisionalBirthIdentity provisionalSupervisor)
                <> "\n"
            )
        )
      exitImmediately (ExitFailure 124)

awaitAnchorSupervisorEvent ::
  SpawnedHelper ->
  IO (Maybe SupervisorEvent)
awaitAnchorSupervisorEvent supervisor = mask $ \restore -> do
  wake <- newEmptyMVar
  supervisorDone <- newEmptyMVar
  parentDone <- newEmptyMVar
  supervisorWatcher <-
    forkIO
      ( finally
          ( try @IOException
              ( readJsonFrameHandle
                  "supervisor event"
                  (spawnedHelperOutput supervisor)
              )
              >>= putMVar wake . AnchorPreparationSupervisor
          )
          (putMVar supervisorDone ())
      )
  parentWatcher <-
    forkIO
      ( finally
          ( try @IOException (restore (awaitHandleEof stdin))
              >>= putMVar wake . AnchorPreparationParentClosed
          )
          (putMVar parentDone ())
      )
  observed <- restore (takeMVar wake)
  case observed of
    AnchorPreparationParentClosed parentResult -> do
      killThread supervisorWatcher
      takeMVar supervisorDone
      takeMVar parentDone
      either ioError (const (pure Nothing)) parentResult
    AnchorPreparationSupervisor eventResult -> do
      killThread parentWatcher
      takeMVar parentDone
      takeMVar supervisorDone
      Just <$> either ioError pure eventResult

validateAnchorSelfIdentity :: ActivityProcessIdentity -> IO ()
validateAnchorSelfIdentity expectedIdentity = do
  processId <- getProcessID
  processGroup <- getProcessGroupID
  observedBirthIdentity <-
    readProcessBirthIdentity (fromIntegral processId)
  unless
    ( activityProcessId expectedIdentity == fromIntegral processId
        && activityProcessGroup expectedIdentity == fromIntegral processGroup
        && observedBirthIdentity
          == Just (activityProcessBirthIdentity expectedIdentity)
    )
    ( ioError
        (userError "bounded-command anchor cannot verify its exact self identity")
    )

cleanupAnchorOwnedSupervisor ::
  Maybe FilePath ->
  ActivityProcessIdentity ->
  SpawnedHelper ->
  MVar (Maybe ActivityProcessIdentity) ->
  MVar (Maybe ProvisionalProcessIdentity) ->
  MVar (Maybe ActivityProcessIdentity) ->
  MVar (Either SomeException ByteString.ByteString) ->
  IO (ExitCode, ByteString.ByteString)
cleanupAnchorOwnedSupervisor
  reapEvidencePrefix
  anchorIdentity
  supervisor
  supervisorFinalState
  pinProvisionalState
  targetGroupLeaderState
  supervisorErrorResult = mask_ $ do
    let trackedSupervisor = spawnedHelperTracked supervisor
        provisionalSupervisor =
          provisionalFromActivityIdentity
            (trackedHelperIdentity trackedSupervisor)
    supervisorFinal <- readMVar supervisorFinalState
    pinProvisional <- readMVar pinProvisionalState
    targetGroupLeader <- readMVar targetGroupLeaderState
    let supervisorContinue =
          maybe
            (signalProvisionalProcessWith sigCONT provisionalSupervisor)
            ( signalOwnedUnreapedHelperGroupWith
                sigCONT
                trackedSupervisor
            )
            supervisorFinal
        pinContinue =
          case targetGroupLeader of
            Just identity -> [signalActivityProcessGroupWith sigCONT identity]
            Nothing ->
              maybe
                []
                (pure . signalProvisionalProcessWith sigCONT)
                pinProvisional
    runCleanupsPreservingFailures
      ( [ ignoreIOException (hClose (spawnedHelperInput supervisor)),
          ignoreIOException supervisorContinue
        ]
          <> map ignoreIOException pinContinue
      )
    awaitHelperProtocolClose (spawnedHelperOutput supervisor)
    let forceNestedGroups = do
          case targetGroupLeader of
            Just identity ->
              ignoreIOException (signalActivityProcessGroup identity)
            Nothing ->
              mapM_
                (ignoreIOException . signalProvisionalProcessWith sigKILL)
                pinProvisional
        forceLiveSupervisor = do
          maybe
            ( ignoreIOException
                (signalProvisionalProcessWith sigKILL provisionalSupervisor)
            )
            ( ignoreIOException
                . signalOwnedUnreapedHelperGroupWith
                  sigKILL
                  trackedSupervisor
            )
            supervisorFinal
    forceNestedGroups
    forceLiveSupervisor
    supervisorExit <-
      waitForTrackedHelperBounded trackedSupervisor
    let supervisorEvidenceIdentity =
          fromMaybe
            (trackedHelperIdentity trackedSupervisor)
            supervisorFinal
    mapM_
      ( \evidencePrefix ->
          recordReapEvidence
            (evidencePrefix <> ".anchor.json")
            anchorIdentity
            [ ( "supervisor",
                ReapedRegisteredChild supervisorEvidenceIdentity,
                show supervisorExit
              )
            ]
      )
      reapEvidencePrefix
    ignoreIOException (hClose (spawnedHelperOutput supervisor))
    case targetGroupLeader of
      Just identity ->
        awaitRecordedProcessGroupAbsent
          "anchor-owned target"
          identity
          500
      Nothing ->
        mapM_
          (awaitProvisionalProcessQuiescent "anchor-owned provisional pin")
          pinProvisional
    case supervisorFinal of
      Just identity ->
        awaitRecordedProcessGroupAbsent
          "anchor-owned supervisor"
          identity
          500
      Nothing ->
        awaitProvisionalProcessQuiescent
          "anchor-owned provisional supervisor"
          provisionalSupervisor
    diagnosticResult <-
      takeMVarBounded "supervisor stderr capture" supervisorErrorResult
    diagnostic <-
      case diagnosticResult of
        Left failure -> pure (ByteString8.pack failure)
        Right (Left failure) ->
          pure (ByteString8.pack (displayException failure))
        Right (Right contents) -> pure contents
    pure (supervisorExit, diagnostic)

drainHandle ::
  Int ->
  Handle ->
  MVar (Either SomeException ByteString.ByteString) ->
  IO ()
drainHandle maximumBytes handle result = do
  captured <-
    try @SomeException
      ( finallyPreservingPrimary
          (readHandleToEnd maximumBytes handle)
          (ignoreIOException (hClose handle))
      )
  putMVar result captured

readHandleToEnd ::
  Int ->
  Handle ->
  IO ByteString.ByteString
readHandleToEnd maximumBytes handle =
  go 0 [] False
  where
    go bytesRead chunks overflowed = do
      contents <- ByteString.hGetSome handle 32768
      if ByteString.null contents
        then
          if overflowed
            then
              ioError
                (userError "bounded-command capture exceeds its size limit")
            else pure (ByteString.concat (reverse chunks))
        else
          if overflowed || ByteString.length contents > maximumBytes - bytesRead
            then go bytesRead [] True
            else
              go
                (bytesRead + ByteString.length contents)
                (contents : chunks)
                False

runInternalSupervisor :: IO ()
runInternalSupervisor = do
  mapM_ prepareProtocolHandle [stdin, stdout, stderr]
  result <-
    try @SomeException $ do
      publishCurrentHelperIdentity "target supervisor"
      superviseTarget
  case result of
    Right exitCode -> exitImmediately exitCode
    Left failure -> do
      ignoreIOException
        ( writeJsonFrameHandle
            stdout
            ( SupervisorTerminal
                ( TargetKernelFailure
                    ("runBoundedCommand supervisor: " <> displayException failure)
                )
                InputCompleted
                (CaptureCompleted ByteString.empty)
                (CaptureCompleted ByteString.empty)
            )
        )
      exitImmediately (ExitFailure 125)

runInternalPin :: IO ()
runInternalPin = do
  mapM_ prepareProtocolHandle [stdin, stdout, stderr]
  result <-
    try @SomeException $ do
      publishCurrentHelperIdentity "target-group pin"
      runPinProtocol
  case result of
    Right () -> exitImmediately ExitSuccess
    Left _ -> exitImmediately (ExitFailure 125)

runPinProtocol :: IO ()
runPinProtocol = do
  detachRequest <-
    readJsonFrameHandle "pin request" stdin
  case detachRequest of
    PinDetach -> pure ()
    PinRetain ->
      ioError
        (userError "bounded-command pin received retain authority before detach")
  setProcessGroupIDOf 0 0
  targetGroupIdentity <-
    requireCurrentActivityIdentity "target-group pin"
  unless
    ( activityProcessId targetGroupIdentity
        == activityProcessGroup targetGroupIdentity
    )
    (ioError (userError "bounded-command pin did not become its group leader"))
  writeJsonFrameHandle
    stdout
    (PinTargetGroupReady targetGroupIdentity)
  retainRequest <-
    readJsonFrameHandle "pin request" stdin
  case retainRequest of
    PinDetach ->
      ioError (userError "bounded-command pin received duplicate detach authority")
    PinRetain -> pure ()
  retainedIdentity <-
    requireCurrentActivityIdentity "retained target-group pin"
  unless (retainedIdentity == targetGroupIdentity) $
    ioError
      (userError "bounded-command pin identity changed before retention")
  writeJsonFrameHandle stdout PinRetained
  forever (awaitSignal Nothing)

data TargetStreams = TargetStreams
  { targetInputReader :: !Fd,
    targetInputWriter :: !Fd,
    targetOutputReader :: !Fd,
    targetOutputWriter :: !Fd,
    targetErrorReader :: !Fd,
    targetErrorWriter :: !Fd
  }

data RetainedProvisioningMutationWorkingDirectory
  = RetainedProvisioningMutationWorkingDirectory
      !ProvisioningMutationWorkingDirectoryWire
      ![Fd]
      !Fd
      !(Maybe RetainedProvisioningRelativeExecutable)
      !(Maybe RetainedProvisioningRelativeExecutable)
      !(Maybe ExecutableSnapshotExpectation)

data RetainedProvisioningRelativeExecutable
  = RetainedProvisioningRelativeExecutable
      !FilePath
      ![Fd]
      !Fd
      !FilePath
      !FileStatus

openRetainedProvisioningMutationWorkingDirectory ::
  SupervisorPlan ->
  IO (Maybe RetainedProvisioningMutationWorkingDirectory)
openRetainedProvisioningMutationWorkingDirectory plan =
  case supervisorPlanProvisioningMutationWorkingDirectory plan of
    Nothing -> pure Nothing
    Just
      wire@( ProvisioningMutationWorkingDirectoryWire
               wireRoot
               components
               relativeExecutable
             ) ->
        mask $ \restore -> do
          root <-
            either
              (ioError . userError . Text.unpack . mutationOutcomeFailure)
              pure
              (provisioningMutationRootFromWire wireRoot)
          rootDescriptor <-
            restore
              ( openFd
                  (provisioningMutationRootPath root)
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      directory = True,
                      cloexec = True
                    }
              )
          let closeOpened descriptors =
                runCleanupsPreservingFailures
                  (map (ignoreIOException . closeFd) (reverse descriptors))
              openComponents descriptors currentDescriptor remaining =
                case remaining of
                  [] -> do
                    retainedExecutable <-
                      mapM
                        ( \executable ->
                            openRetainedProvisioningRelativeExecutable
                              currentDescriptor
                              executable
                              (supervisorPlanExecutable plan)
                              (supervisorPlanRetainedExecutableExpectation plan)
                        )
                        relativeExecutable
                    retainedNestedExecutable <-
                      onExceptionPreservingPrimary
                        ( mapM
                            ( \expectation ->
                                let nestedRelativeExecutable =
                                      Provisioning.installedSmokeExecutableRelativePath
                                        (sourceIsolationExpectationAdapter expectation)
                                    configuredNestedExecutable =
                                      mutationWireRootPath wireRoot
                                        </> nestedRelativeExecutable
                                 in openRetainedProvisioningRelativeExecutable
                                      currentDescriptor
                                      nestedRelativeExecutable
                                      configuredNestedExecutable
                                      Nothing
                            )
                            (supervisorPlanInstalledPythonSourceIsolationExpectation plan)
                        )
                        ( mapM_
                            (ignoreIOException . closeRetainedProvisioningRelativeExecutable)
                            retainedExecutable
                        )
                    pure
                      ( RetainedProvisioningMutationWorkingDirectory
                          wire
                          descriptors
                          currentDescriptor
                          retainedExecutable
                          retainedNestedExecutable
                          (supervisorPlanRetainedExecutableExpectation plan)
                      )
                  component : rest -> do
                    childDescriptor <-
                      restore
                        ( openFdAt
                            (Just currentDescriptor)
                            component
                            ReadOnly
                            defaultFileFlags
                              { nofollow = True,
                                directory = True,
                                cloexec = True
                              }
                        )
                    openedStatus <- getFdStatus childDescriptor
                    unless
                      (isDirectory openedStatus)
                      ( ioError
                          (userError "provisioning mutation cwd component is not a real directory")
                      )
                    onExceptionPreservingPrimary
                      ( openComponents
                          (descriptors <> [childDescriptor])
                          childDescriptor
                          rest
                      )
                      (closeOpened (descriptors <> [childDescriptor]))
          retained <-
            onExceptionPreservingPrimary
              ( do
                  rootStatus <- getFdStatus rootDescriptor
                  rootPathStatus <-
                    getSymbolicLinkStatus
                      (provisioningMutationRootPath root)
                  unless
                    ( mutationRootStatusMatches root rootStatus
                        && mutationRootStatusMatches root rootPathStatus
                        && not (isSymbolicLink rootPathStatus)
                    )
                    (ioError (userError "provisioning mutation cwd root identity changed"))
                  openComponents [rootDescriptor] rootDescriptor components
              )
              (closeOpened [rootDescriptor])
          onExceptionPreservingPrimary
            (validateRetainedProvisioningMutationWorkingDirectory retained)
            (closeRetainedProvisioningMutationWorkingDirectory retained)
          pure (Just retained)

validateRetainedProvisioningMutationWorkingDirectory ::
  RetainedProvisioningMutationWorkingDirectory ->
  IO ()
validateRetainedProvisioningMutationWorkingDirectory
  ( RetainedProvisioningMutationWorkingDirectory
      ( ProvisioningMutationWorkingDirectoryWire
          wireRoot
          components
          _relativeExecutable
        )
      descriptors
      finalDescriptor
      retainedExecutable
      retainedNestedExecutable
      retainedExecutableExpectation
    ) = do
    validate
    mapM_
      (validateRetainedProvisioningRelativeExecutable finalDescriptor)
      retainedExecutable
    mapM_
      (validateRetainedProvisioningRelativeExecutable finalDescriptor)
      retainedNestedExecutable
    mapM_
      (validateRetainedExecutableExpectation finalDescriptor retainedExecutable)
      retainedExecutableExpectation
    where
      validate = do
        root <-
          either
            (ioError . userError . Text.unpack . mutationOutcomeFailure)
            pure
            (provisioningMutationRootFromWire wireRoot)
        case descriptors of
          [] ->
            ioError (userError "provisioning mutation cwd retained no root descriptor")
          rootDescriptor : _ -> do
            rootDescriptorStatus <- getFdStatus rootDescriptor
            rootPathStatus <-
              getSymbolicLinkStatus (provisioningMutationRootPath root)
            unless
              ( mutationRootStatusMatches root rootDescriptorStatus
                  && mutationRootStatusMatches root rootPathStatus
                  && not (isSymbolicLink rootPathStatus)
                  && length descriptors == length components + 1
              )
              (ioError (userError "provisioning mutation cwd root changed during custody"))
            mapM_
              validateComponent
              (zip3 descriptors components (drop 1 descriptors))
        getFdStatus
          finalDescriptor
          >>= \status ->
            unless
              (isDirectory status)
              (ioError (userError "provisioning mutation cwd final descriptor is invalid"))
      validateComponent (parentDescriptor, component, childDescriptor) = do
        reopenedDescriptor <-
          openFdAt
            (Just parentDescriptor)
            component
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        finallyPreservingPrimary
          ( do
              retainedStatus <- getFdStatus childDescriptor
              reopenedStatus <- getFdStatus reopenedDescriptor
              unless
                (exactMutationDirectoryStatus retainedStatus reopenedStatus)
                (ioError (userError "provisioning mutation cwd component changed during custody"))
          )
          (ignoreIOException (closeFd reopenedDescriptor))

openRetainedProvisioningRelativeExecutable ::
  Fd ->
  FilePath ->
  FilePath ->
  Maybe ExecutableSnapshotExpectation ->
  IO RetainedProvisioningRelativeExecutable
openRetainedProvisioningRelativeExecutable
  workingDirectoryDescriptor
  relativePath
  configuredPath
  retainedExpectation =
    case reverse (splitDirectories relativePath) of
      [] ->
        ioError (userError "provisioning relative executable is empty")
      executableLeaf : reversedDirectoryComponents ->
        mask $ \restore -> do
          let directoryComponents = reverse reversedDirectoryComponents
              closeDirectories =
                runCleanupsPreservingFailures
                  . map (ignoreIOException . closeFd)
                  . reverse
              openDirectories parentDescriptor opened components =
                case components of
                  [] -> pure (parentDescriptor, opened)
                  component : rest -> do
                    descriptor <-
                      restore
                        ( openFdAt
                            (Just parentDescriptor)
                            component
                            ReadOnly
                            defaultFileFlags
                              { nofollow = True,
                                directory = True,
                                cloexec = True
                              }
                        )
                    status <- getFdStatus descriptor
                    unless
                      (isDirectory status)
                      (ioError (userError "provisioning relative executable parent is not a directory"))
                    onExceptionPreservingPrimary
                      (openDirectories descriptor (opened <> [descriptor]) rest)
                      (closeDirectories (opened <> [descriptor]))
          (parentDescriptor, directoryDescriptors) <-
            openDirectories
              workingDirectoryDescriptor
              []
              directoryComponents
          listedConfiguredStatus <- getSymbolicLinkStatus configuredPath
          executableDescriptor <-
            onExceptionPreservingPrimary
              ( restore
                  ( openFdAt
                      (Just parentDescriptor)
                      executableLeaf
                      ReadOnly
                      defaultFileFlags
                        { nofollow = isNothing retainedExpectation,
                          cloexec = True
                        }
                  )
              )
              (closeDirectories directoryDescriptors)
          onExceptionPreservingPrimary
            ( do
                status <- getFdStatus executableDescriptor
                finalConfiguredStatus <-
                  getSymbolicLinkStatus configuredPath
                unless
                  ( isRegularFile status
                      && exactFileStatusMatches
                        listedConfiguredStatus
                        finalConfiguredStatus
                      && fileMode status
                        .&. ( PosixFiles.ownerExecuteMode
                                .|. PosixFiles.groupExecuteMode
                                .|. PosixFiles.otherExecuteMode
                            )
                        /= 0
                  )
                  (ioError (userError "provisioning relative executable is not a real executable file"))
                pure
                  ( RetainedProvisioningRelativeExecutable
                      relativePath
                      directoryDescriptors
                      executableDescriptor
                      configuredPath
                      finalConfiguredStatus
                  )
            )
            ( runCleanupsPreservingFailures
                [ ignoreIOException (closeFd executableDescriptor),
                  closeDirectories directoryDescriptors
                ]
            )

validateRetainedProvisioningRelativeExecutable ::
  Fd ->
  RetainedProvisioningRelativeExecutable ->
  IO ()
validateRetainedProvisioningRelativeExecutable
  workingDirectoryDescriptor
  ( RetainedProvisioningRelativeExecutable
      relativePath
      retainedDirectoryDescriptors
      retainedExecutableDescriptor
      configuredPath
      retainedConfiguredStatus
    ) =
    case reverse (splitDirectories relativePath) of
      [] ->
        ioError (userError "retained provisioning relative executable is empty")
      executableLeaf : reversedDirectoryComponents ->
        validateDirectories
          workingDirectoryDescriptor
          (reverse reversedDirectoryComponents)
          retainedDirectoryDescriptors
          >>= \parentDescriptor -> do
            reopenedExecutable <-
              openFdAt
                (Just parentDescriptor)
                executableLeaf
                ReadOnly
                defaultFileFlags
                  { nofollow = not (isSymbolicLink retainedConfiguredStatus),
                    cloexec = True
                  }
            finallyPreservingPrimary
              ( do
                  retainedStatus <- getFdStatus retainedExecutableDescriptor
                  reopenedStatus <- getFdStatus reopenedExecutable
                  configuredStatus <- getSymbolicLinkStatus configuredPath
                  unless
                    ( exactFileStatusMatches retainedStatus reopenedStatus
                        && exactFileStatusMatches
                          retainedConfiguredStatus
                          configuredStatus
                        && isRegularFile reopenedStatus
                    )
                    (ioError (userError "provisioning relative executable changed during custody"))
              )
              (ignoreIOException (closeFd reopenedExecutable))
    where
      validateDirectories
        parentDescriptor
        components
        retainedDescriptors =
          case (components, retainedDescriptors) of
            ([], []) -> pure parentDescriptor
            (component : rest, retained : retainedRest) -> do
              reopened <-
                openFdAt
                  (Just parentDescriptor)
                  component
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      directory = True,
                      cloexec = True
                    }
              finallyPreservingPrimary
                ( do
                    retainedStatus <- getFdStatus retained
                    reopenedStatus <- getFdStatus reopened
                    unless
                      (exactMutationDirectoryStatus retainedStatus reopenedStatus)
                      (ioError (userError "provisioning relative executable parent changed"))
                    validateDirectories retained rest retainedRest
                )
                (ignoreIOException (closeFd reopened))
            _ ->
              ioError
                (userError "provisioning relative executable descriptor shape changed")

validateRetainedExecutableExpectation ::
  Fd ->
  Maybe RetainedProvisioningRelativeExecutable ->
  ExecutableSnapshotExpectation ->
  IO ()
validateRetainedExecutableExpectation
  _workingDirectoryDescriptor
  retainedExecutable
  expectation =
    case retainedExecutable of
      Nothing ->
        ioError
          (userError "retained executable expectation has no relative target")
      Just
        ( RetainedProvisioningRelativeExecutable
            _relativePath
            _directoryDescriptors
            executableDescriptor
            configuredPath
            _configuredStatus
          ) -> do
          canonicalPath <- canonicalizePath configuredPath
          status <- getFdStatus executableDescriptor
          digest <- digestRetainedExecutableDescriptor executableDescriptor status
          unless
            ( normalise configuredPath
                == normalise (snapshotConfiguredPath expectation)
                && normalise canonicalPath
                  == normalise (snapshotCanonicalPath expectation)
                && exactExecutableStatusMatches expectation status
                && digest == snapshotDigest expectation
                && isNothing (snapshotTestHook expectation)
            )
            (ioError (userError "retained executable identity disagreed"))
          mapM_
            verifyRetainedPackageClosure
            (snapshotPackageClosures expectation)
          mapM_
            verifyRetainedRuntimeLibrary
            (snapshotRuntimeLibraries expectation)

digestRetainedExecutableDescriptor ::
  Fd ->
  FileStatus ->
  IO Text.Text
digestRetainedExecutableDescriptor descriptor status = do
  _ <- fdSeek descriptor AbsoluteSeek 0
  context <-
    hashSnapshotDescriptor
      descriptor
      (fromIntegral (PosixFiles.fileSize status))
      SHA256.init
  _ <- fdSeek descriptor AbsoluteSeek 0
  pure
    ( "sha256:"
        <> TextEncoding.decodeUtf8
          (Base16.encode (SHA256.finalize context))
    )

closeRetainedProvisioningRelativeExecutable ::
  RetainedProvisioningRelativeExecutable ->
  IO ()
closeRetainedProvisioningRelativeExecutable
  ( RetainedProvisioningRelativeExecutable
      _
      directoryDescriptors
      executableDescriptor
      _
      _
    ) =
    runCleanupsPreservingFailures
      ( ignoreIOException (closeFd executableDescriptor)
          : map
            (ignoreIOException . closeFd)
            (reverse directoryDescriptors)
      )

retainedProvisioningMutationWorkingDirectoryDescriptor ::
  RetainedProvisioningMutationWorkingDirectory ->
  Fd
retainedProvisioningMutationWorkingDirectoryDescriptor
  (RetainedProvisioningMutationWorkingDirectory _ _ finalDescriptor _ _ _) =
    finalDescriptor

retainedProvisioningMutationRelativeExecutable ::
  RetainedProvisioningMutationWorkingDirectory ->
  Maybe FilePath
retainedProvisioningMutationRelativeExecutable
  ( RetainedProvisioningMutationWorkingDirectory
      ( ProvisioningMutationWorkingDirectoryWire
          _wireRoot
          _components
          relativeExecutable
        )
      _
      _
      _
      _
      _
    ) =
    relativeExecutable

closeRetainedProvisioningMutationWorkingDirectory ::
  RetainedProvisioningMutationWorkingDirectory ->
  IO ()
closeRetainedProvisioningMutationWorkingDirectory
  ( RetainedProvisioningMutationWorkingDirectory
      _
      descriptors
      _
      retainedExecutable
      retainedNestedExecutable
      _
    ) =
    runCleanupsPreservingFailures
      ( maybe
          []
          ( \executable ->
              [ ignoreIOException
                  (closeRetainedProvisioningRelativeExecutable executable)
              ]
          )
          retainedExecutable
          <> maybe
            []
            ( \executable ->
                [ ignoreIOException
                    (closeRetainedProvisioningRelativeExecutable executable)
                ]
            )
            retainedNestedExecutable
          <> map (ignoreIOException . closeFd) (reverse descriptors)
      )

mutationOutcomeFailure ::
  ProvisioningFilesystemMutationOutcome ->
  Text.Text
mutationOutcomeFailure outcome =
  case outcome of
    ProvisioningMutationSucceeded -> "unexpected successful mutation outcome"
    ProvisioningMutationRejectedSpec failure -> failure
    ProvisioningMutationKernelFailure failure -> failure
    ProvisioningMutationTimedOut (Timeout micros) ->
      "mutation timed out after "
        <> Text.pack (show micros)
        <> " microseconds"

-- | A supervisor-local thread owns the opaque FileLock token. The only
-- operation available to the supervisor state machine is one-shot release,
-- which waits until the locking region has actually unwound.
data SupervisorGenerationLeaseCustody
  = SupervisorGenerationLeaseCustody
      !(MVar ())
      !(MVar (Either SomeException ()))

acquireSupervisorGenerationLease ::
  SupervisorPlan ->
  IO (Maybe SupervisorGenerationLeaseCustody)
acquireSupervisorGenerationLease plan =
  case supervisorPlanArtifactGenerationLeaseExpectation plan of
    Nothing -> do
      unless
        (isNothing (supervisorPlanArtifactLeaseExpectation plan))
        ( ioError
            ( userError
                "bounded installed artifact helper lacks an exact generation lease"
            )
        )
      pure Nothing
    Just expectation -> mask $ \restore -> do
      generationLease <-
        either
          (ioError . userError)
          pure
          (artifactGenerationLeaseFromExpectation expectation)
      acquired <- newEmptyMVar
      release <- newEmptyMVar
      completed <- newEmptyMVar
      void
        ( forkIO $ do
            result <-
              try @SomeException $ do
                locked <-
                  withTryArtifactGenerationReadLock generationLease $ do
                    validateSupervisorArtifactGenerationLease
                      plan
                      generationLease
                    putMVar acquired (Right ())
                    takeMVar release
                case locked of
                  Nothing ->
                    ioError
                      ( userError
                          "artifact generation read lease is contended"
                      )
                  Just () -> pure ()
            case result of
              Left failure -> do
                void (tryPutMVar acquired (Left failure))
                putMVar completed (Left failure)
              Right () -> do
                void (tryPutMVar acquired (Right ()))
                putMVar completed (Right ())
        )
      let custody = SupervisorGenerationLeaseCustody release completed
          abandonAcquisition = do
            void (tryPutMVar release ())
            void (takeMVar completed)
      acquisition <-
        onExceptionPreservingPrimary
          (restore (takeMVar acquired))
          abandonAcquisition
      case acquisition of
        Left failure -> throwIO failure
        Right () -> pure (Just custody)

releaseSupervisorGenerationLease ::
  SupervisorGenerationLeaseCustody ->
  IO ()
releaseSupervisorGenerationLease
  (SupervisorGenerationLeaseCustody release completed) = do
    void (tryPutMVar release ())
    result <- takeMVar completed
    either throwIO pure result

validateSupervisorArtifactGenerationLease ::
  SupervisorPlan ->
  ArtifactGenerationLease ->
  IO ()
validateSupervisorArtifactGenerationLease plan generationLease = do
  let ( enginesRoot,
        generationAdapterId,
        expectedGenerationFingerprint,
        expectedPayloadDigest
        ) =
          artifactGenerationLeaseFields
            generationLease
  identity <-
    maybe
      (ioError (userError "artifact generation lease has no closed adapter identity"))
      pure
      (ArtifactIdentity.parseNativeArtifactIdentity generationAdapterId)
  artifactRoot <- supervisorArtifactGenerationRoot plan
  unless
    ( normalise (takeDirectory artifactRoot) == normalise enginesRoot
        && normalise artifactRoot == artifactRoot
    )
    ( ioError
        ( userError
            "artifact generation lease does not name the exact retained artifact root"
        )
    )
  case supervisorPlanArtifactLeaseExpectation plan of
    Nothing -> do
      lane@(candidateSubstrate, candidateArchitecture) <-
        maybe
          ( ioError
              ( userError
                  "artifact generation lease expectation names no closed target lane"
              )
          )
          (pure . artifactGenerationLeaseExpectationLane)
          (supervisorPlanArtifactGenerationLeaseExpectation plan)
      candidateRuntimeExpectation <-
        artifactRuntimeExpectationForLane candidateSubstrate candidateArchitecture
      validateRetainedArtifactTarget plan identity lane artifactRoot
      -- Re-digest the retained payload from bytes before it is used as an input
      -- to the generation identity below, so the identity is rebuilt on observed
      -- bytes rather than on the digest the parent asserted.
      Artifact.validateArtifactGenerationPayloadLease
        artifactRoot
        expectedPayloadDigest
      -- A pre-manifest candidate has no manifest to validate against, so its
      -- generation identity is rebuilt from the closed catalog and re-observed
      -- target evidence instead. The superseded assertion here was
      -- @generationFingerprint == payloadDigest@, which is only the
      -- @apple-silicon@ construction: a @linux-native@ generation binds the
      -- recipe, target contract, and image evidence too, so it is never its own
      -- payload digest and no Linux candidate smoke could pass on any input.
      rederived <-
        Artifact.rederiveArtifactGenerationFingerprint
          identity
          candidateRuntimeExpectation
          artifactRoot
          expectedPayloadDigest
      candidateGenerationFingerprint <-
        either
          ( ioError
              . userError
              . ("re-derive candidate artifact generation identity: " <>)
          )
          pure
          rederived
      unless
        (candidateGenerationFingerprint == expectedGenerationFingerprint)
        ( ioError
            ( userError
                "candidate artifact generation fingerprint is not the identity its own lane, recipe, target contract, and observed evidence produce"
            )
        )
    Just artifactExpectation -> do
      unless
        (isNothing (supervisorPlanExecutableSnapshot plan))
        ( ioError
            ( userError
                "bounded artifact command cannot snapshot its installed direct target"
            )
        )
      unless
        ( artifactLeaseAdapterId artifactExpectation == generationAdapterId
            && normalise (artifactLeaseInstallRoot artifactExpectation)
              == normalise artifactRoot
        )
        ( ioError
            ( userError
                "bounded artifact validation and generation leases disagree"
            )
        )
      runtimeExpectation <-
        artifactRuntimeExpectationForLane
          (artifactLeaseSubstrate artifactExpectation)
          (artifactLeaseArchitecture artifactExpectation)
      -- The retained-shape rule is not weaker for an activated generation than
      -- for a candidate: an installed target must retain exactly one safe
      -- relative executable and an image target must retain none, so neither
      -- shape can pass as the other. This branch previously skipped that check
      -- entirely, which only went unnoticed because nothing reached it.
      validateRetainedArtifactTarget
        plan
        identity
        ( artifactLeaseSubstrate artifactExpectation,
          artifactLeaseArchitecture artifactExpectation
        )
        artifactRoot
      target <-
        either
          (ioError . userError)
          pure
          ( ArtifactTarget.nativeArtifactTarget
              identity
              (artifactLeaseSubstrate artifactExpectation)
              (artifactLeaseArchitecture artifactExpectation)
          )
      let expectedExecutable =
            ArtifactTarget.nativeArtifactTargetExecutable artifactRoot target
      unless
        (normalise (supervisorPlanExecutable plan) == normalise expectedExecutable)
        ( ioError
            ( userError
                "bounded artifact target disagrees with the closed direct-target catalog"
            )
        )
      Artifact.validateEngineArtifactHelperLease
        identity
        runtimeExpectation
        artifactRoot
        (artifactLeaseManifestFingerprint artifactExpectation)
        expectedGenerationFingerprint
        expectedPayloadDigest

-- | The one place a named lane becomes a runtime expectation. Both the
-- candidate and the installed branch resolve through it, so neither can admit a
-- lane the other refuses. The Linux expectation names the running host's
-- architecture, so a lease naming a different one fails closed downstream rather
-- than being silently reinterpreted.
artifactRuntimeExpectationForLane ::
  Text.Text ->
  Text.Text ->
  IO Artifact.ArtifactRuntimeExpectation
artifactRuntimeExpectationForLane substrate architecture =
  case substrate of
    "apple-silicon"
      | architecture == "arm64" ->
          pure Artifact.appleArtifactRuntimeExpectation
    "linux-native"
      | architecture `elem` ["amd64", "arm64"] ->
          pure Artifact.linuxArtifactRuntimeExpectation
    _ ->
      ioError
        (userError "bounded artifact lease has an unsupported runtime lane")

supervisorArtifactGenerationRoot :: SupervisorPlan -> IO FilePath
supervisorArtifactGenerationRoot plan =
  case ( supervisorPlanArtifactLeaseExpectation plan,
         supervisorPlanProvisioningMutationWorkingDirectory plan
       ) of
    (Just artifactExpectation, Nothing) ->
      pure (artifactLeaseInstallRoot artifactExpectation)
    ( Just artifactExpectation,
      Just (ProvisioningMutationWorkingDirectoryWire mutationWireRoot [] _)
      )
        | normalise (artifactLeaseInstallRoot artifactExpectation)
            == normalise (mutationWireRootPath mutationWireRoot) ->
            pure (mutationWireRootPath mutationWireRoot)
    ( Nothing,
      Just
        ( ProvisioningMutationWorkingDirectoryWire
            mutationWireRoot
            []
            -- Deliberately either shape. An installed candidate retains one
            -- safe relative executable and an image candidate retains none,
            -- because it execs an absolute path the immutable image owns. This
            -- position previously demanded @Just _@, which refused every image
            -- candidate before its root was even resolved. The shape is not
            -- unchecked as a result: 'validateRetainedArtifactTarget' requires
            -- it to agree with 'nativeArtifactTargetIsInstalled' for the closed
            -- catalog entry, which is a stronger rule than either constructor
            -- alone.
            _
          )
      ) ->
        pure (mutationWireRootPath mutationWireRoot)
    _ ->
      ioError
        ( userError
            "artifact generation helper lacks one exact retained artifact root"
        )

validateRetainedArtifactTarget ::
  SupervisorPlan ->
  ArtifactIdentity.NativeArtifactIdentity ->
  (Text.Text, Text.Text) ->
  FilePath ->
  IO ()
validateRetainedArtifactTarget plan identity (substrate, architecture) artifactRoot = do
  target <-
    either
      (ioError . userError)
      pure
      (ArtifactTarget.nativeArtifactTarget identity substrate architecture)
  let expectedExecutable =
        ArtifactTarget.nativeArtifactTargetExecutable artifactRoot target
      expectedRelativeExecutable =
        makeRelative artifactRoot expectedExecutable
      -- An installed target is retained as one safe relative executable under
      -- the generation root. An image target has none: it execs an absolute
      -- path the immutable image owns, and the retained root is present only
      -- because it is the generation whose manifest and loader closure
      -- authorize the run. Both shapes still require the exact retained root.
      exactRetainedTarget =
        case supervisorPlanProvisioningMutationWorkingDirectory plan of
          Just
            ( ProvisioningMutationWorkingDirectoryWire
                mutationWireRoot
                []
                retainedRelativeExecutable
              ) ->
              normalise (mutationWireRootPath mutationWireRoot)
                == normalise artifactRoot
                && retainedRelativeExecutable
                  == ( if ArtifactTarget.nativeArtifactTargetIsInstalled target
                         then Just expectedRelativeExecutable
                         else Nothing
                     )
          _ -> False
  case supervisorPlanInstalledPythonSourceIsolationExpectation plan of
    Nothing ->
      unless
        ( normalise (supervisorPlanExecutable plan)
            == normalise expectedExecutable
            && exactRetainedTarget
        )
        ( ioError
            ( userError
                "candidate artifact target disagrees with the closed direct-target catalog"
            )
        )
    Just expectation -> do
      let adapter = sourceIsolationExpectationAdapter expectation
          expectedNestedRelativeExecutable =
            Provisioning.installedSmokeExecutableRelativePath adapter
          expectedArguments =
            Provisioning.installedPythonSourceIsolationArgumentsForPaths
              adapter
              artifactRoot
              (sourceIsolationExpectationDirectoryPaths expectation)
              (sourceIsolationExpectationFilePaths expectation)
              ( runtimeLibrarySnapshotCanonicalPath
                  (sourceIsolationExpectationWritableProbe expectation)
              )
              (sourceIsolationExpectationReceiptDigest expectation)
          exactWrapperRoot =
            case supervisorPlanProvisioningMutationWorkingDirectory plan of
              Just
                ( ProvisioningMutationWorkingDirectoryWire
                    mutationWireRoot
                    []
                    Nothing
                  ) ->
                  normalise (mutationWireRootPath mutationWireRoot)
                    == normalise artifactRoot
              _ -> False
      unless
        ( ArtifactTarget.nativeArtifactTargetIsInstalled target
            && Text.pack (Provisioning.appleAdapterSlug adapter)
              == ArtifactIdentity.nativeArtifactAdapterId identity
            && normalise expectedNestedRelativeExecutable
              == normalise expectedRelativeExecutable
            && normalise (supervisorPlanExecutable plan)
              == normalise Provisioning.installedPythonSourceIsolationSandboxExecutable
            && supervisorPlanArguments plan == expectedArguments
            && exactWrapperRoot
        )
        ( ioError
            ( userError
                "source-isolated artifact target disagrees with the closed nested-target catalog"
            )
        )

validateInstalledPythonSourceIsolationSources :: SupervisorPlan -> IO ()
validateInstalledPythonSourceIsolationSources plan =
  case supervisorPlanInstalledPythonSourceIsolationExpectation plan of
    Nothing -> pure ()
    Just expectation -> do
      verifyRetainedPlatformExecutable
        (sourceIsolationExpectationAuditInjector expectation)
      mapM_
        verifyRetainedPackageClosure
        (sourceIsolationExpectationDirectories expectation)
      mapM_
        verifyRetainedRuntimeLibrary
        (sourceIsolationExpectationFiles expectation)
      verifyWritableSourceIsolationProbe
        (sourceIsolationExpectationWritableProbe expectation)

verifyRetainedPlatformExecutable ::
  ExecutableSnapshotExpectation ->
  IO ()
verifyRetainedPlatformExecutable expectation = do
  canonicalPath <- canonicalizePath (snapshotConfiguredPath expectation)
  unless
    ( normalise canonicalPath == normalise (snapshotCanonicalPath expectation)
        && systemPlatformBinaryPath canonicalPath
    )
    (ioError (userError "source-isolation platform executable canonical path changed"))
  status <- getSymbolicLinkStatus canonicalPath
  digest <- digestSealedSnapshotFile canonicalPath
  unless
    ( exactExecutableStatusMatches expectation status
        && digest == snapshotDigest expectation
        && null (snapshotPackageClosures expectation)
        && null (snapshotRuntimeLibraries expectation)
        && isNothing (snapshotTestHook expectation)
    )
    (ioError (userError "source-isolation platform executable identity changed"))

verifyWritableSourceIsolationProbe ::
  RuntimeLibrarySnapshotExpectation ->
  IO ()
verifyWritableSourceIsolationProbe expectation = do
  verifyRetainedRuntimeLibrary expectation
  descriptor <-
    openFd
      (runtimeLibrarySnapshotCanonicalPath expectation)
      WriteOnly
      defaultFileFlags
        { nofollow = True,
          cloexec = True
        }
  finallyPreservingPrimary
    ( do
        status <- getFdStatus descriptor
        unless
          (exactRuntimeLibraryStatusMatches expectation status)
          (ioError (userError "source-isolation writable probe identity changed"))
    )
    (ignoreIOException (closeFd descriptor))

superviseTarget :: IO ExitCode
superviseTarget = mask $ \restore -> do
  initialRequest <-
    restore (readJsonFrameHandle "supervisor request" stdin)
  plan <-
    case initialRequest of
      SupervisorConfigure configuredPlan -> pure configuredPlan
      SupervisorDetach ->
        ioError
          (userError "bounded-command supervisor received detach before configuration")
      SupervisorAcknowledgePin ->
        ioError
          (userError "bounded-command supervisor received pin custody before configuration")
      SupervisorOpenTargetGate ->
        ioError
          (userError "bounded-command supervisor received gate authority before configuration")
  validateSupervisorAnchorCustody (supervisorPlanAnchorIdentity plan)
  pin <-
    spawnSelfExecHelperWithGroup
      InheritHelperProcessGroup
      (supervisorPlanHelperEnvironment plan)
      internalPinMode
  pinGroupIdentity <- newMVar Nothing
  mutationWorkingDirectoryState <- newMVar Nothing
  generationLeaseCustodyState <- newMVar Nothing
  pinErrorResult <- newEmptyMVar
  void
    ( forkIO
        ( drainHandle
            maximumHelperDiagnosticBytes
            (spawnedHelperError pin)
            pinErrorResult
        )
    )
  let provisionalPinIdentity =
        provisionalFromActivityIdentity
          (trackedHelperIdentity (spawnedHelperTracked pin))
      closeMutationWorkingDirectoryState =
        modifyMVar_
          mutationWorkingDirectoryState
          ( \retained -> do
              mapM_
                (ignoreIOException . closeRetainedProvisioningMutationWorkingDirectory)
                retained
              pure Nothing
          )
      closeGenerationLeaseCustodyState =
        modifyMVar_
          generationLeaseCustodyState
          ( \custody -> do
              mapM_ releaseSupervisorGenerationLease custody
              pure Nothing
          )
      cleanupPin =
        runCleanupsPreservingFailures
          [ closeMutationWorkingDirectoryState,
            cleanupSelfExecPin pin pinGroupIdentity pinErrorResult,
            closeGenerationLeaseCustodyState
          ]
      anchorIdentity = supervisorPlanAnchorIdentity plan
  supervisorProcessId <- fromIntegral <$> getProcessID
  supervisorProcessGroup <- fromIntegral <$> getProcessGroupID
  unless
    ( provisionalProcessGroup provisionalPinIdentity
        == supervisorProcessGroup
        && supervisorProcessGroup == activityProcessGroup anchorIdentity
        && provisionalProcessId provisionalPinIdentity
          /= supervisorProcessId
        && provisionalProcessId provisionalPinIdentity
          /= activityProcessId anchorIdentity
    )
    ( finallyPreservingPrimary
        (ioError (userError "bounded-command pin was not born in anchor custody"))
        cleanupPin
    )
  onExceptionPreservingPrimary
    ( restore $ do
        writeJsonFrameHandle
          stdout
          (SupervisorPinBorn provisionalPinIdentity)
        runSupervisorCustodyHandoffStopHook plan provisionalPinIdentity
        custodyRequest <-
          readJsonFrameHandle "supervisor request" stdin
        case custodyRequest of
          SupervisorAcknowledgePin -> pure ()
          SupervisorDetach ->
            ioError (userError "bounded-command supervisor received detach before pin custody")
          SupervisorConfigure _ ->
            ioError
              (userError "bounded-command supervisor received duplicate configuration")
          SupervisorOpenTargetGate ->
            ioError
              (userError "bounded-command supervisor received target gate before pin custody")
        detachRequest <-
          readJsonFrameHandle "supervisor request" stdin
        case detachRequest of
          SupervisorDetach -> pure ()
          SupervisorConfigure _ ->
            ioError
              (userError "bounded-command supervisor received duplicate configuration")
          SupervisorAcknowledgePin ->
            ioError
              (userError "bounded-command supervisor received duplicate pin custody")
          SupervisorOpenTargetGate ->
            ioError
              (userError "bounded-command supervisor received target gate before detach")
        setProcessGroupIDOf 0 0
        runSupervisorPrePreparedStopHook plan provisionalPinIdentity
        validateSupervisorSelfGroup
        detachedSupervisorIdentity <-
          requireCurrentActivityIdentity "detached supervisor"
        writeJsonFrameHandle
          stdout
          (SupervisorDetached detachedSupervisorIdentity)
        writeJsonFrameHandle
          (spawnedHelperInput pin)
          PinDetach
        pinEvent <-
          readJsonFrameHandle
            "pin event"
            (spawnedHelperOutput pin)
        detachedPinIdentity <-
          case pinEvent of
            PinTargetGroupReady identity -> pure identity
            PinRetained ->
              ioError
                (userError "bounded-command pin retained before group transition")
        validateCustodyTransition
          "target-group pin"
          provisionalPinIdentity
          detachedPinIdentity
        modifyMVar_
          pinGroupIdentity
          (const (pure (Just detachedPinIdentity)))
        retainedMutationWorkingDirectory <-
          openRetainedProvisioningMutationWorkingDirectory plan
        modifyMVar_
          mutationWorkingDirectoryState
          (const (pure retainedMutationWorkingDirectory))
        writeJsonFrameHandle
          stdout
          (SupervisorPrepared detachedPinIdentity)
        startRequest <-
          readJsonFrameHandle "supervisor request" stdin
        case startRequest of
          SupervisorOpenTargetGate -> pure ()
          SupervisorDetach ->
            ioError
              (userError "bounded-command supervisor received duplicate detach")
          SupervisorConfigure _ ->
            ioError
              (userError "bounded-command supervisor received duplicate configuration")
          SupervisorAcknowledgePin ->
            ioError
              (userError "bounded-command supervisor received duplicate pin custody")
        generationLeaseCustody <-
          mask_ (acquireSupervisorGenerationLease plan)
        mask_
          ( modifyMVar_
              generationLeaseCustodyState
              (const (pure generationLeaseCustody))
          )
        writeJsonFrameHandle
          (spawnedHelperInput pin)
          PinRetain
        retainedEvent <-
          readJsonFrameHandle
            "pin event"
            (spawnedHelperOutput pin)
        case retainedEvent of
          PinRetained -> pure ()
          PinTargetGroupReady _ ->
            ioError
              (userError "bounded-command pin sent duplicate group transition")
        validateObservedActivityLeader
          "retained target-group pin"
          detachedPinIdentity
        ignoreIOException (hClose (spawnedHelperInput pin))
    )
    cleanupPin
  retainedPinIdentity <-
    requireSessionIdentity "retained target-group pin" pinGroupIdentity
  mutationWorkingDirectory <- readMVar mutationWorkingDirectoryState
  let closeMutationWorkingDirectory =
        closeMutationWorkingDirectoryState
  streams <-
    onExceptionPreservingPrimary
      createTargetStreams
      (runCleanupsPreservingFailures [closeMutationWorkingDirectory, cleanupPin])
  (gateReader, gateWriter) <-
    onExceptionPreservingPrimary
      createPrivatePipe
      ( runCleanupsPreservingFailures
          [ closeTargetStreams streams,
            closeMutationWorkingDirectory,
            cleanupPin
          ]
      )
  (execReader, execWriter) <-
    onExceptionPreservingPrimary
      createPrivatePipe
      ( runCleanupsPreservingFailures
          [ closePipeDescriptors gateReader gateWriter,
            closeTargetStreams streams,
            closeMutationWorkingDirectory,
            cleanupPin
          ]
      )
  target <-
    onExceptionPreservingPrimary
      ( spawnSupervisorTarget
          plan
          mutationWorkingDirectory
          retainedPinIdentity
          streams
          gateReader
          gateWriter
          execReader
          execWriter
      )
      ( runCleanupsPreservingFailures
          [ closePipeDescriptors execReader execWriter,
            closePipeDescriptors gateReader gateWriter,
            closeTargetStreams streams,
            closeMutationWorkingDirectory,
            cleanupPin
          ]
      )
  let cleanupTarget =
        finallyPreservingPrimary
          ( finallyPreservingPrimary
              ( do
                  terminal <-
                    cleanupSupervisorTarget
                      plan
                      pin
                      retainedPinIdentity
                      pinErrorResult
                      target
                      gateWriter
                      execReader
                  mapM_
                    validateRetainedProvisioningMutationWorkingDirectory
                    mutationWorkingDirectory
                  validateInstalledPythonSourceIsolationSources plan
                  pure terminal
              )
              closeMutationWorkingDirectory
          )
          closeGenerationLeaseCustodyState
      cleanupBeforeWorkers =
        runCleanupsPreservingFailures
          [ ignoreIOException (closeFd gateReader),
            ignoreIOException (closeFd execWriter),
            closeTargetStreams streams,
            void cleanupTarget
          ]
  onExceptionPreservingPrimary
    ( runCleanupsPreservingFailures
        [ closeFd gateReader,
          closeFd execWriter,
          closeFd (targetInputReader streams),
          closeFd (targetOutputWriter streams),
          closeFd (targetErrorWriter streams)
        ]
    )
    cleanupBeforeWorkers
  inputResult <- newEmptyMVar
  stdoutResult <- newEmptyMVar
  stderrResult <- newEmptyMVar
  void
    ( forkIO
        ( writeTargetInputFd
            (targetInputWriter streams)
            (supervisorPlanInput plan)
            inputResult
        )
    )
  void
    ( forkIO
        ( drainTargetFd
            (targetOutputReader streams)
            stdoutResult
        )
    )
  void
    ( forkIO
        ( drainTargetFd
            (targetErrorReader streams)
            stderrResult
        )
    )
  let cleanupTargetAndWorkers = do
        terminal <- cleanupTarget
        evidence <-
          collectTargetStreamEvidence inputResult stdoutResult stderrResult
        pure (terminal, evidence)
  gateStart <-
    try @IOException
      (writeFdFully gateWriter (ByteString8.pack "start\n"))
  terminal <-
    case gateStart of
      Left gateFailure ->
        finallyPreservingPrimary
          ( ioError
              ( userError
                  ( "runBoundedCommand: target gate failed: "
                      <> displayException gateFailure
                  )
              )
          )
          (void cleanupTargetAndWorkers)
      Right () -> do
        execReport <-
          onExceptionPreservingPrimary
            (readTrackedTargetExecReport True target execReader)
            (void cleanupTargetAndWorkers)
        if not (ByteString.null execReport)
          then do
            closeFd gateWriter
            void (waitForTrackedProcessBounded target)
            cleanupTarget
          else do
            runSupervisorSynchronousExceptionReadyHook
              plan
              retainedPinIdentity
              target
            runSupervisorProtocolIsolationReadyHook
              plan
              retainedPinIdentity
              target
            wake <-
              onExceptionPreservingPrimary
                ( do
                    closeFd gateWriter
                    if supervisorPlanForceControlFailure plan
                      then do
                        void (waitForTrackedProcessBounded target)
                        pure
                          ( SupervisorControlFailed
                              "parent-control read failed: forced test failure"
                          )
                      else
                        waitForSupervisorWake
                          plan
                          pin
                          retainedPinIdentity
                          target
                )
                (void cleanupTargetAndWorkers)
            case wake of
              SupervisorTargetTerminal -> do
                targetTerminal <- cleanupTarget
                mapM_
                  ( \evidencePrefix ->
                      recordSupervisorReapEvidence
                        (evidencePrefix <> ".supervisor.json")
                        target
                        (spawnedHelperTracked pin)
                        retainedPinIdentity
                  )
                  (supervisorPlanReapEvidencePrefix plan)
                pure targetTerminal
              SupervisorPinTerminal -> do
                void cleanupTarget
                pure
                  ( TargetKernelFailure
                      "runBoundedCommand: retained target-group pin exited before target cleanup"
                  )
              SupervisorParentClosed -> do
                void cleanupTargetAndWorkers
                exitImmediately ExitSuccess
              SupervisorControlFailed failure -> do
                void cleanupTarget
                pure (TargetKernelFailure failure)
  evidence <-
    collectTargetStreamEvidence inputResult stdoutResult stderrResult
  let (inputEvidence, stdoutEvidence, stderrEvidence) = evidence
      (reportedTerminal, reportedStdoutEvidence, reportedStderrEvidence) =
        applySupervisorTerminalEvidenceFixture
          (supervisorPlanProtocolEvidenceCase plan)
          terminal
          stdoutEvidence
          stderrEvidence
  writeJsonFrameHandle
    stdout
    ( SupervisorTerminal
        reportedTerminal
        inputEvidence
        reportedStdoutEvidence
        reportedStderrEvidence
    )
  case terminal of
    TargetKernelFailure _ -> pure (ExitFailure 125)
    _ -> pure ExitSuccess

applySupervisorTerminalEvidenceFixture ::
  Maybe TestProtocolEvidenceCase ->
  TargetTerminal ->
  CaptureEvidence ->
  CaptureEvidence ->
  (TargetTerminal, CaptureEvidence, CaptureEvidence)
applySupervisorTerminalEvidenceFixture
  maybeEvidenceCase
  terminal
  stdoutEvidence
  stderrEvidence =
    case maybeEvidenceCase of
      Just ProtocolCaptureAtLimit ->
        ( terminal,
          CaptureCompleted
            (ByteString.replicate maximumCapturedOutputBytes 120),
          stderrEvidence
        )
      Just ProtocolCaptureOverLimit ->
        ( terminal,
          CaptureCompleted
            (ByteString.replicate (maximumCapturedOutputBytes + 1) 120),
          stderrEvidence
        )
      Just ProtocolTargetExitAtLimit ->
        (TargetExited maximumProtocolExitCode, stdoutEvidence, stderrEvidence)
      Just ProtocolTargetExitNegative ->
        (TargetExited (-1), stdoutEvidence, stderrEvidence)
      Just ProtocolTargetExitOverLimit ->
        (TargetExited (maximumProtocolExitCode + 1), stdoutEvidence, stderrEvidence)
      Just ProtocolTargetSignalAtLimit ->
        ( TargetSignaled maximumProtocolSignalNumber False,
          stdoutEvidence,
          stderrEvidence
        )
      Just ProtocolTargetSignalZero ->
        (TargetSignaled 0 False, stdoutEvidence, stderrEvidence)
      Just ProtocolTargetSignalNegative ->
        (TargetSignaled (-1) False, stdoutEvidence, stderrEvidence)
      Just ProtocolTargetSignalOverLimit ->
        ( TargetSignaled (maximumProtocolSignalNumber + 1) False,
          stdoutEvidence,
          stderrEvidence
        )
      _ -> (terminal, stdoutEvidence, stderrEvidence)

applySupervisorExitEvidenceFixture ::
  Maybe TestProtocolEvidenceCase ->
  ExitCode ->
  ExitCode
applySupervisorExitEvidenceFixture maybeEvidenceCase supervisorExit =
  case maybeEvidenceCase of
    Just ProtocolSupervisorExitAtLimit ->
      ExitFailure maximumProtocolExitCode
    Just ProtocolSupervisorExitNegative ->
      ExitFailure (-1)
    Just ProtocolSupervisorExitOverLimit ->
      ExitFailure (maximumProtocolExitCode + 1)
    _ -> supervisorExit

validateSupervisorSelfGroup :: IO ()
validateSupervisorSelfGroup = do
  processId <- getProcessID
  processGroup <- getProcessGroupID
  unless (processGroup == processId) $
    ioError
      (userError "bounded-command supervisor is not its own process-group leader")

validateSupervisorAnchorCustody ::
  ActivityProcessIdentity ->
  IO ()
validateSupervisorAnchorCustody anchorIdentity = do
  anchorBirthIdentityBefore <-
    readProcessBirthIdentity (activityProcessId anchorIdentity)
  processId <- getProcessID
  processGroup <- getProcessGroupID
  anchorBirthIdentityAfter <-
    readProcessBirthIdentity (activityProcessId anchorIdentity)
  unless
    ( anchorBirthIdentityBefore
        == Just (activityProcessBirthIdentity anchorIdentity)
        && anchorBirthIdentityAfter
          == Just (activityProcessBirthIdentity anchorIdentity)
        && processId /= fromIntegral (activityProcessId anchorIdentity)
        && fromIntegral processGroup == activityProcessGroup anchorIdentity
    )
    (ioError (userError "bounded-command supervisor is outside anchor custody"))

runSupervisorPrePreparedStopHook ::
  SupervisorPlan ->
  ProvisionalProcessIdentity ->
  IO ()
runSupervisorPrePreparedStopHook plan pinIdentity =
  case supervisorPlanPrePreparedStopPath plan of
    Nothing -> pure ()
    Just readyPath -> do
      processId <- getProcessID
      supervisorBirthIdentity <-
        readProcessBirthIdentity (fromIntegral processId)
          >>= maybe
            ( ioError
                ( userError
                    "bounded-command supervisor cannot observe its pre-prepared birth identity"
                )
            )
            pure
      let anchorIdentity = supervisorPlanAnchorIdentity plan
      ByteString8.writeFile
        readyPath
        ( ByteString8.pack
            ( show (activityProcessId anchorIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity anchorIdentity)
                <> "\n"
                <> show processId
                <> "\n"
                <> renderProcessBirthIdentity supervisorBirthIdentity
                <> "\n"
                <> show (provisionalProcessId pinIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (provisionalBirthIdentity pinIdentity)
                <> "\n"
            )
        )
      signalProcess sigSTOP processId

runSupervisorCustodyHandoffStopHook ::
  SupervisorPlan ->
  ProvisionalProcessIdentity ->
  IO ()
runSupervisorCustodyHandoffStopHook plan pinIdentity =
  case supervisorPlanCustodyHandoffStopPath plan of
    Nothing -> pure ()
    Just readyPath -> do
      processId <- getProcessID
      supervisorBirthIdentity <-
        readProcessBirthIdentity (fromIntegral processId)
          >>= maybe
            ( ioError
                ( userError
                    "bounded-command supervisor cannot observe its custody-handoff birth identity"
                )
            )
            pure
      let anchorIdentity = supervisorPlanAnchorIdentity plan
      ByteString8.writeFile
        readyPath
        ( ByteString8.pack
            ( show (activityProcessId anchorIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity anchorIdentity)
                <> "\n"
                <> show processId
                <> "\n"
                <> renderProcessBirthIdentity supervisorBirthIdentity
                <> "\n"
                <> show (provisionalProcessId pinIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (provisionalBirthIdentity pinIdentity)
                <> "\n"
            )
        )
      signalProcess sigSTOP processId

runSupervisorProtocolIsolationReadyHook ::
  SupervisorPlan ->
  ActivityProcessIdentity ->
  TrackedProcess ->
  IO ()
runSupervisorProtocolIsolationReadyHook plan pinIdentity target =
  case supervisorPlanProtocolIsolationReadyPath plan of
    Nothing -> pure ()
    Just readyPath -> do
      targetStatus <- readMVar (trackedProcessStatus target)
      unless
        ( isNothing targetStatus
            && trackedProcessGroup target
              == activityProcessGroup pinIdentity
        )
        ( ioError
            ( userError
                "bounded-command protocol-isolation target lacks unreaped ownership"
            )
        )
      validateProcessInRegisteredGroup
        "protocol-isolation target"
        (fromIntegral (trackedProcessId target))
        (activityProcessGroup pinIdentity)
        pinIdentity
      validateObservedGroupMember
        "protocol-isolation target"
        (trackedProcessIdentity target)
      ByteString8.writeFile
        readyPath
        ( ByteString8.pack
            ( show (activityProcessId (trackedProcessIdentity target))
                <> "\n"
                <> show (activityProcessGroup (trackedProcessIdentity target))
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity (trackedProcessIdentity target))
                <> "\n"
                <> show (activityProcessId pinIdentity)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity pinIdentity)
                <> "\n"
            )
        )

runSupervisorSynchronousExceptionReadyHook ::
  SupervisorPlan ->
  ActivityProcessIdentity ->
  TrackedProcess ->
  IO ()
runSupervisorSynchronousExceptionReadyHook plan pinIdentity target =
  case supervisorPlanSynchronousExceptionIdentityPath plan of
    Nothing -> pure ()
    Just identityPath -> do
      targetStatus <- readMVar (trackedProcessStatus target)
      unless
        ( isNothing targetStatus
            && trackedProcessGroup target
              == activityProcessGroup pinIdentity
        )
        ( ioError
            ( userError
                "bounded-command synchronous target lacks unreaped ownership"
            )
        )
      descendantIdentity <-
        awaitSynchronousDescendantProcess
          identityPath
          pinIdentity
      let evidence =
            SynchronousExceptionTreeEvidence
              { synchronousTargetIdentity = trackedProcessIdentity target,
                synchronousDescendantIdentity = descendantIdentity,
                synchronousGroupLeaderIdentity = pinIdentity
              }
      validateSynchronousExceptionTree pinIdentity evidence
      LazyByteString.writeFile identityPath (Aeson.encode evidence)

awaitSynchronousDescendantProcess ::
  FilePath ->
  ActivityProcessIdentity ->
  IO ActivityProcessIdentity
awaitSynchronousDescendantProcess identityPath pinIdentity = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.pollLimitedDeadline 10000 5 5 501)
      observeIdentity
  Readiness.foldReadiness
    pure
    (const timedOut)
    (const timedOut)
    outcome
  where
    observeIdentity = do
      exists <- doesFileExist identityPath
      if not exists
        then pure waiting
        else do
          initialStatus <- getSymbolicLinkStatus identityPath
          contents <- ByteString8.readFile identityPath
          finalStatus <- getSymbolicLinkStatus identityPath
          if not
            ( isRegularFile initialStatus
                && not (isSymbolicLink initialStatus)
                && exactFileStatusMatches initialStatus finalStatus
                && ByteString.length contents
                  <= maximumTargetSetupFrameBytes + 9
            )
            then pure waiting
            else observeDecodedIdentity (decodeTargetSetupFrameBytes contents)
    observeDecodedIdentity decoded =
      case decoded of
        Left _ -> pure waiting
        Right (HelperIdentityReady identity)
          | activityProcessGroup identity
              == activityProcessGroup pinIdentity -> do
              validateObservedGroupMember
                "synchronous descendant"
                identity
              pure (Right identity)
          | otherwise -> pure waiting
    waiting =
      Left
        ( Readiness.Progress
            0
            1
            "waiting for synchronous-exception descendant identity"
        )
    timedOut =
      ioError
        ( userError
            "bounded-command synchronous-exception descendant was not observable"
        )

decodeTargetSetupFrameBytes ::
  (Aeson.FromJSON value) =>
  ByteString.ByteString ->
  Either String value
decodeTargetSetupFrameBytes framed = do
  unless
    (ByteString.length framed >= 9)
    (Left "target-setup frame is truncated")
  let (header, encoded) = ByteString.splitAt 9 framed
      (hexLength, newline) = ByteString8.splitAt 8 header
      parsedLength =
        case readHex (ByteString8.unpack hexLength) of
          [(value, "")] -> Just value
          _ -> Nothing
  frameLength <-
    case (parsedLength, newline) of
      (Just value, suffix)
        | suffix == ByteString8.pack "\n",
          value >= 0,
          value <= maximumTargetSetupFrameBytes ->
            Right value
      _ -> Left "target-setup frame header is invalid"
  unless
    (ByteString.length encoded == frameLength)
    (Left "target-setup frame length is invalid")
  Aeson.eitherDecodeStrict' encoded

createPrivatePipe :: IO (Fd, Fd)
createPrivatePipe = mask $ \restore -> do
  (reader, writer) <- createPipe
  onExceptionPreservingPrimary
    ( restore $ do
        setFdOption reader CloseOnExec True
        setFdOption writer CloseOnExec True
        pure (reader, writer)
    )
    (closePipeDescriptors reader writer)

closePipeDescriptors :: Fd -> Fd -> IO ()
closePipeDescriptors reader writer =
  runCleanupsPreservingFailures
    [ ignoreIOException (closeFd writer),
      ignoreIOException (closeFd reader)
    ]

createTargetStreams :: IO TargetStreams
createTargetStreams = mask_ $ do
  (inputReader, inputWriter) <- createPrivatePipe
  (outputReader, outputWriter) <-
    onExceptionPreservingPrimary
      createPrivatePipe
      (closePipeDescriptors inputReader inputWriter)
  (errorReader, errorWriter) <-
    onExceptionPreservingPrimary
      createPrivatePipe
      ( runCleanupsPreservingFailures
          [ closePipeDescriptors outputReader outputWriter,
            closePipeDescriptors inputReader inputWriter
          ]
      )
  pure
    TargetStreams
      { targetInputReader = inputReader,
        targetInputWriter = inputWriter,
        targetOutputReader = outputReader,
        targetOutputWriter = outputWriter,
        targetErrorReader = errorReader,
        targetErrorWriter = errorWriter
      }

closeTargetStreams :: TargetStreams -> IO ()
closeTargetStreams streams =
  runCleanupsPreservingFailures
    ( map
        (ignoreIOException . closeFd)
        [ targetInputReader streams,
          targetInputWriter streams,
          targetOutputReader streams,
          targetOutputWriter streams,
          targetErrorReader streams,
          targetErrorWriter streams
        ]
    )

spawnSupervisorTarget ::
  SupervisorPlan ->
  Maybe RetainedProvisioningMutationWorkingDirectory ->
  ActivityProcessIdentity ->
  TargetStreams ->
  Fd ->
  Fd ->
  Fd ->
  Fd ->
  IO TrackedProcess
spawnSupervisorTarget
  plan
  mutationWorkingDirectory
  pinIdentity
  streams
  gateReader
  gateWriter
  execReader
  execWriter = mask $ \restore -> do
    registrationState <- newMVar Nothing
    processId <-
      forkProcess
        ( runSupervisorTargetChild
            plan
            mutationWorkingDirectory
            pinIdentity
            streams
            gateReader
            gateWriter
            execReader
            execWriter
        )
    let abortTarget =
          runCleanupsPreservingFailures
            [ ignoreIOException (signalProcess sigKILL processId),
              do
                requireBoundedProcessReap "supervisor target" processId
                modifyMVar_
                  registrationState
                  ( \registration -> do
                      mapM_
                        ProcessIdentityInternal.releaseRegisteredProcessIdentity
                        registration
                      pure Nothing
                  )
            ]
    onExceptionPreservingPrimary
      ( restore $ do
          setProcessGroupIDOf
            processId
            (fromIntegral (activityProcessGroup pinIdentity))
          setupEvent <-
            readJsonFrameFd
              "target setup"
              execReader
          case setupEvent of
            TargetSetupFailed failure ->
              ioError
                ( userError
                    ( "bounded-command target setup failed before its start gate: "
                        <> failure
                    )
                )
            TargetIdentityReady _ ->
              ioError
                (userError "bounded-command target skipped its birth event")
            TargetBorn reportedProcessId reportedProcessGroup ->
              unless
                ( reportedProcessId == fromIntegral processId
                    && reportedProcessGroup
                      == activityProcessGroup pinIdentity
                )
                ( ioError
                    (userError "bounded-command target setup identity is invalid")
                )
          observedProcessGroup <-
            fromIntegral <$> getProcessGroupIDOf processId
          unless
            ( observedProcessGroup
                == activityProcessGroup pinIdentity
            )
            ( ioError
                (userError "bounded-command target did not join its retained group")
            )
          registration <-
            ProcessIdentityInternal.registerOwnedChildProcessIdentity
              (fromIntegral processId)
          modifyMVar_
            registrationState
            ( \case
                Nothing -> pure (Just registration)
                Just _ ->
                  ioError
                    (userError "bounded-command target acquired duplicate registration")
            )
          let (registeredProcessId, registeredBirthIdentity) =
                ProcessIdentityInternal.registeredProcessIdentity registration
              exactIdentity =
                ActivityProcessIdentity
                  { activityProcessId = registeredProcessId,
                    activityProcessGroup = activityProcessGroup pinIdentity,
                    activityProcessBirthIdentity = registeredBirthIdentity
                  }
          unless (registeredProcessId == fromIntegral processId) $
            ioError
              (userError "bounded-command target registration names the wrong child")
          validateObservedGroupMember "newly registered target" exactIdentity
          writeFdFully gateWriter (ByteString8.pack "identity\n")
          identityEvent <-
            readJsonFrameFd
              "target identity"
              execReader
          case identityEvent of
            TargetIdentityReady reportedIdentity ->
              unless (reportedIdentity == exactIdentity) $
                ioError
                  (userError "bounded-command target reported a mismatched exact identity")
            TargetBorn _ _ ->
              ioError
                (userError "bounded-command target sent a duplicate birth event")
            TargetSetupFailed failure ->
              ioError
                ( userError
                    ( "bounded-command target setup failed before exact identity: "
                        <> failure
                    )
                )
          validateObservedGroupMember "registered target" exactIdentity
          status <- newMVar Nothing
          execReport <- newMVar Nothing
          pure
            TrackedProcess
              { trackedProcessId = processId,
                trackedProcessGroup = activityProcessGroup pinIdentity,
                trackedProcessIdentity = exactIdentity,
                trackedProcessRegistration = registrationState,
                trackedProcessStatus = status,
                trackedProcessExecReport = execReport
              }
      )
      abortTarget

runSupervisorTargetChild ::
  SupervisorPlan ->
  Maybe RetainedProvisioningMutationWorkingDirectory ->
  ActivityProcessIdentity ->
  TargetStreams ->
  Fd ->
  Fd ->
  Fd ->
  Fd ->
  IO ()
runSupervisorTargetChild
  plan
  mutationWorkingDirectory
  pinIdentity
  streams
  gateReader
  gateWriter
  execReader
  execWriter = do
    setupResult <-
      try @SomeException $ do
        dropInheritedProcessIdentity
        setProcessGroupIDOf
          0
          (fromIntegral (activityProcessGroup pinIdentity))
        void (dupTo (targetInputReader streams) stdInput)
        void (dupTo (targetOutputWriter streams) stdOutput)
        void (dupTo (targetErrorWriter streams) stdError)
        mapM_
          (\descriptor -> setFdOption descriptor NonBlockingRead False)
          [stdInput, stdOutput, stdError]
        mapM_
          (ignoreIOException . closeFd)
          [ targetInputReader streams,
            targetInputWriter streams,
            targetOutputReader streams,
            targetOutputWriter streams,
            targetErrorReader streams,
            targetErrorWriter streams,
            gateWriter,
            execReader
          ]
        processId <- fromIntegral <$> getProcessID
        processGroup <- fromIntegral <$> getProcessGroupID
        unless
          ( processId > 0
              && processGroup == activityProcessGroup pinIdentity
          )
          (ioError (userError "bounded-command target child joined an invalid group"))
        writeJsonFrameFd
          execWriter
          (TargetBorn processId processGroup)
        identitySignal <- readFdExactly gateReader 9
        unless (identitySignal == ByteString8.pack "identity\n") $
          ioError
            (userError "bounded-command target identity gate was invalid")
        birthIdentity <-
          readProcessBirthIdentity processId
            >>= maybe
              (ioError (userError "bounded-command target birth registration is absent"))
              pure
        let exactIdentity =
              ActivityProcessIdentity
                { activityProcessId = processId,
                  activityProcessGroup = processGroup,
                  activityProcessBirthIdentity = birthIdentity
                }
        validateTargetExecutableSnapshot plan
        mapM_
          validateRetainedProvisioningMutationWorkingDirectory
          mutationWorkingDirectory
        when
          (supervisorPlanForceTargetSetupFailure plan)
          (ioError (userError "forced pre-gate target setup failure"))
        writeJsonFrameFd
          execWriter
          (TargetIdentityReady exactIdentity)
    case setupResult of
      Left failure -> do
        reportResult <-
          try @IOException
            ( writeJsonFrameFd
                execWriter
                ( TargetSetupFailed
                    (take 1024 (displayException failure))
                )
            )
        case reportResult of
          Right () -> pure ()
          Left _ -> pure ()
        exitImmediately (ExitFailure 126)
      Right () -> pure ()
    executionResult <-
      try @IOException $ do
        startSignal <- readFdExactly gateReader 6
        unless (startSignal == ByteString8.pack "start\n") $
          ioError
            (userError "bounded-command target gate closed without start")
        closeFd gateReader
        validateTargetExecutableSnapshot plan
        case mutationWorkingDirectory of
          Nothing ->
            mapM_
              setCurrentDirectory
              (supervisorPlanWorkingDirectory plan)
          Just retained -> do
            validateRetainedProvisioningMutationWorkingDirectory retained
            PosixDirectory.changeWorkingDirectoryFd
              (retainedProvisioningMutationWorkingDirectoryDescriptor retained)
        executable <-
          case mutationWorkingDirectory
            >>= retainedProvisioningMutationRelativeExecutable of
            Just retainedExecutable -> pure retainedExecutable
            Nothing
              | supervisorPlanExecutable plan
                  == internalSelfExecutableSentinel,
                isJust (supervisorPlanSynchronousExceptionIdentityPath plan) ->
                  getExecutablePath
              | otherwise -> pure (supervisorPlanExecutable plan)
        validateInstalledPythonSourceIsolationSources plan
        executeFile
          executable
          False
          (supervisorPlanArguments plan)
          (Just (supervisorPlanEnvironment plan))
    case executionResult of
      Left failure -> do
        reportResult <-
          try @IOException
            (writeExecFailureReport execWriter failure)
        case reportResult of
          Right () -> pure ()
          Left _ -> pure ()
        exitImmediately (ExitFailure 126)
      Right () -> exitImmediately ExitSuccess

waitForSupervisorWake ::
  SupervisorPlan ->
  SpawnedHelper ->
  ActivityProcessIdentity ->
  TrackedProcess ->
  IO SupervisorWake
waitForSupervisorWake plan pin pinIdentity target = do
  wake <- newEmptyMVar
  void (forkIO (watchTargetTerminal wake))
  void
    ( forkIO $ do
        pinResult <-
          try @IOException (awaitHandleEof (spawnedHelperOutput pin))
        let pinWake =
              case pinResult of
                Right () -> SupervisorPinTerminal
                Left failure ->
                  SupervisorControlFailed
                    ("pin-control read failed: " <> displayException failure)
        putMVar wake pinWake
    )
  void
    ( forkIO $ do
        controlResult <- try @IOException (awaitHandleEof stdin)
        case controlResult of
          Right () -> putMVar wake SupervisorParentClosed
          Left failure ->
            putMVar
              wake
              ( SupervisorControlFailed
                  ("parent-control read failed: " <> displayException failure)
              )
    )
  takeMVar wake
  where
    watchTargetTerminal wake = do
      maybeStatus <- waitForTrackedProcessMaybe target
      case maybeStatus of
        Nothing -> watchTargetTerminal wake
        Just _ -> do
          observation <-
            try @IOException
              (runSupervisorTerminalObservationHook plan pinIdentity target)
          case observation of
            Left failure ->
              putMVar
                wake
                ( SupervisorControlFailed
                    ( "terminal-observation hook failed: "
                        <> displayException failure
                    )
                )
            Right deferredToParentClose ->
              unless deferredToParentClose $
                putMVar wake SupervisorTargetTerminal

awaitHandleEof :: Handle -> IO ()
awaitHandleEof handle = do
  contents <- ByteString.hGetSome handle 1
  unless (ByteString.null contents) $
    ioError
      (userError "bounded-command liveness stream carried unexpected data")

runSupervisorTerminalObservationHook ::
  SupervisorPlan ->
  ActivityProcessIdentity ->
  TrackedProcess ->
  IO Bool
runSupervisorTerminalObservationHook plan pin target =
  case supervisorPlanTerminalObservationPath plan of
    Nothing -> pure False
    Just observationPath -> do
      targetStatus <- readMVar (trackedProcessStatus target)
      case targetStatus of
        Nothing ->
          ioError
            ( userError
                "bounded-command terminal-observation hook ran before target reap"
            )
        Just _ -> pure ()
      signalActivityProcessGroupWith sigSTOP pin
      ByteString8.writeFile
        observationPath
        ( ByteString8.pack
            ( show (activityProcessId (trackedProcessIdentity target))
                <> "\n"
                <> show (activityProcessGroup (trackedProcessIdentity target))
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity (trackedProcessIdentity target))
                <> "\n"
                <> show (activityProcessId pin)
                <> "\n"
                <> renderProcessBirthIdentity
                  (activityProcessBirthIdentity pin)
                <> "\n"
            )
        )
      pure True

cleanupSelfExecPin ::
  SpawnedHelper ->
  MVar (Maybe ActivityProcessIdentity) ->
  MVar (Either SomeException ByteString.ByteString) ->
  IO ()
cleanupSelfExecPin pin finalIdentityState errorResult = mask_ $ do
  let trackedPin = spawnedHelperTracked pin
      provisionalPin =
        provisionalFromActivityIdentity (trackedHelperIdentity trackedPin)
  finalIdentity <- readMVar finalIdentityState
  initialResults <-
    mapM
      (try @SomeException)
      ( [ignoreIOException (hClose (spawnedHelperInput pin))]
          <> maybe
            [signalProvisionalProcessWith sigCONT provisionalPin]
            ( \identity ->
                [ signalOwnedUnreapedHelperGroupWith
                    sigCONT
                    trackedPin
                    identity,
                  signalOwnedUnreapedHelperGroupWith
                    sigKILL
                    trackedPin
                    identity
                ]
            )
            finalIdentity
      )
  gracefulExit <- try @SomeException (waitForTrackedHelperMaybe trackedPin)
  forcedResults <-
    case gracefulExit of
      Right (Just _) -> pure []
      _ ->
        mapM
          (try @SomeException)
          ( maybe
              [signalProvisionalProcessWith sigKILL provisionalPin]
              (const [])
              finalIdentity
          )
  reapResult <-
    case gracefulExit of
      Right (Just exitCode) -> pure (Right exitCode)
      _ -> try @SomeException (waitForTrackedHelperBounded trackedPin)
  absenceResult <-
    try @SomeException $
      maybe
        ( awaitProvisionalProcessQuiescent
            "supervisor-owned provisional pin"
            provisionalPin
        )
        ( \identity ->
            awaitRecordedProcessGroupAbsent
              "supervisor-owned target"
              identity
              500
        )
        finalIdentity
  outputCloseResult <-
    try @SomeException (ignoreIOException (hClose (spawnedHelperOutput pin)))
  diagnosticResult <-
    try @SomeException
      (takeMVarBounded "pin stderr capture" errorResult)
  let diagnosticFailures =
        case diagnosticResult of
          Left failure -> [failure]
          Right (Left failure) -> [toException (userError failure)]
          Right (Right (Left failure)) -> [failure]
          Right (Right (Right _)) -> []
      cleanupFailures =
        concatMap exceptionFailures initialResults
          <> concatMap exceptionFailures forcedResults
          <> exceptionFailures gracefulExit
          <> exceptionFailures reapResult
          <> exceptionFailures absenceResult
          <> exceptionFailures outputCloseResult
          <> diagnosticFailures
  runCleanupsPreservingFailures (map throwIO cleanupFailures)

cleanupSupervisorTarget ::
  SupervisorPlan ->
  SpawnedHelper ->
  ActivityProcessIdentity ->
  MVar (Either SomeException ByteString.ByteString) ->
  TrackedProcess ->
  Fd ->
  Fd ->
  IO TargetTerminal
cleanupSupervisorTarget
  plan
  pin
  pinIdentity
  pinErrorResult
  target
  gateWriter
  execReader =
    finallyPreservingPrimary
      ( cleanupSupervisorTargetResult
          plan
          pin
          pinIdentity
          pinErrorResult
          target
          execReader
      )
      (ignoreIOException (closeFd gateWriter))

cleanupSupervisorTargetResult ::
  SupervisorPlan ->
  SpawnedHelper ->
  ActivityProcessIdentity ->
  MVar (Either SomeException ByteString.ByteString) ->
  TrackedProcess ->
  Fd ->
  IO TargetTerminal
cleanupSupervisorTargetResult
  plan
  pin
  pinIdentity
  pinErrorResult
  target
  execReader = mask_ $ do
    gracefulAttempt <-
      case supervisorPlanSynchronousExceptionIdentityPath plan of
        Nothing -> pure (Right ())
        Just _ ->
          try @SomeException
            ( runCleanupsPreservingFailures
                [ signalOwnedUnreapedHelperGroupWith
                    sigCONT
                    (spawnedHelperTracked pin)
                    pinIdentity,
                  signalOwnedUnreapedHelperGroupWith
                    sigTERM
                    (spawnedHelperTracked pin)
                    pinIdentity,
                  void (waitForTrackedProcessMaybe target)
                ]
            )
    groupKillAttempt <-
      try @SomeException
        ( runCleanupsPreservingFailures
            [ signalOwnedUnreapedHelperGroupWith
                sigCONT
                (spawnedHelperTracked pin)
                pinIdentity,
              signalOwnedUnreapedHelperGroupWith
                sigKILL
                (spawnedHelperTracked pin)
                pinIdentity
            ]
        )
    fallbackResult <-
      case groupKillAttempt of
        Left _ ->
          try @SomeException
            ( runCleanupsPreservingFailures
                -- The fallback runs precisely because the group signal already
                -- failed, so an ESRCH or EPERM here is the expected shape and
                -- must not abort the teardown before its absence proof runs.
                -- The deferral discharges only those two errnos; every
                -- identity refusal these primitives raise is a 'userError' and
                -- still propagates.
                [ deferSignalFailureUntilAbsence
                    (signalOwnedUnreapedProcessWith sigKILL target),
                  deferSignalFailureUntilAbsence
                    (signalActivityProcessWith sigKILL pinIdentity)
                ]
            )
        Right () -> pure (Right ())
    targetStatusResult <-
      try @SomeException (waitForTrackedProcessBounded target)
    pinStatusResult <-
      try @SomeException
        (waitForTrackedHelperBounded (spawnedHelperTracked pin))
    pinOutputCloseResult <-
      try @SomeException
        (ignoreIOException (hClose (spawnedHelperOutput pin)))
    terminationProof <-
      try @SomeException
        ( awaitRecordedProcessGroupAbsent
            "supervisor-owned target"
            pinIdentity
            500
        )
    execReportReadResult <-
      case targetStatusResult of
        Right _ ->
          try @SomeException
            (readTrackedTargetExecReport False target execReader)
        Left _ -> pure (Right ByteString.empty)
    execReportCloseResult <-
      try @SomeException (closeFd execReader)
    pinDiagnosticResult <-
      try @SomeException
        (takeMVarBounded "pin stderr capture" pinErrorResult)
    -- EPERM from the group kill is not absence evidence on its own, so it is
    -- discharged only once two independent exact-identity facts hold: the
    -- designated reap of the pin completed, and the recorded group was proven
    -- absent. 'awaitRecordedProcessGroupAbsent' still refuses a leader PID
    -- reused across that observation, so nothing about reuse detection is
    -- relaxed; if either fact is missing the EPERM is reported unchanged.
    let verifiedGroupKill =
          case (groupKillAttempt, pinStatusResult, terminationProof) of
            (Left failure, Right _, Right ())
              | maybe
                  False
                  isPermissionError
                  (fromException failure :: Maybe IOException) ->
                  Right ()
            _ -> groupKillAttempt
        cleanupFailures =
          exceptionFailures gracefulAttempt
            <> exceptionFailures verifiedGroupKill
            <> exceptionFailures fallbackResult
            <> exceptionFailures targetStatusResult
            <> exceptionFailures pinStatusResult
            <> exceptionFailures pinOutputCloseResult
            <> exceptionFailures terminationProof
            <> exceptionFailures execReportReadResult
            <> exceptionFailures execReportCloseResult
            <> exceptionFailures pinDiagnosticResult
    case ( cleanupFailures,
           targetStatusResult,
           execReportReadResult
         ) of
      ([], Right processStatus, Right execReport)
        | ByteString.null execReport ->
            pure (targetTerminalFromStatus processStatus)
        | otherwise ->
            pure (targetTerminalFromExecFailureReport execReport)
      _ -> do
        runCleanupsPreservingFailures (map throwIO cleanupFailures)
        ioError
          (userError "runBoundedCommand: supervisor target cleanup invariant failed")

readTrackedTargetExecReport ::
  Bool ->
  TrackedProcess ->
  Fd ->
  IO ByteString.ByteString
readTrackedTargetExecReport requirePostExecIdentity target execReader =
  modifyMVar
    (trackedProcessExecReport target)
    ( \cachedReport ->
        case cachedReport of
          Just report -> pure (cachedReport, report)
          Nothing -> do
            report <- readFdToEnd 8192 execReader
            when
              (requirePostExecIdentity && ByteString.null report)
              (validateObservedGroupMember "post-exec target" (trackedProcessIdentity target))
            pure (Just report, report)
    )

targetTerminalFromExecFailureReport ::
  ByteString.ByteString ->
  TargetTerminal
targetTerminalFromExecFailureReport execReport =
  case ByteString8.stripPrefix (ByteString8.pack "exec-failed\n") execReport of
    Nothing ->
      TargetKernelFailure "runBoundedCommand: malformed target exec-failure report"
    Just failureBytes ->
      TargetKernelFailure
        ( "runBoundedCommand: target setup/exec failed: "
            <> ByteString8.unpack failureBytes
        )

targetTerminalFromStatus :: ProcessStatus -> TargetTerminal
targetTerminalFromStatus processStatus =
  case processStatus of
    Exited ExitSuccess -> TargetExited 0
    Exited (ExitFailure exitCode) -> TargetExited exitCode
    Terminated signal coreDumped ->
      TargetSignaled (fromIntegral signal) coreDumped
    Stopped signal ->
      TargetKernelFailure
        ("runBoundedCommand: target remained stopped for signal " <> show signal)

writeTargetInputFd ::
  Fd ->
  ByteString.ByteString ->
  MVar (Either SomeException ()) ->
  IO ()
writeTargetInputFd descriptor input result = do
  writeResult <-
    try @SomeException
      ( finallyPreservingPrimary
          (writeFdFully descriptor input)
          (ignoreIOException (closeFd descriptor))
      )
  putMVar result writeResult

drainTargetFd ::
  Fd ->
  MVar (Either SomeException ByteString.ByteString) ->
  IO ()
drainTargetFd descriptor result = do
  readResult <-
    try @SomeException
      ( finallyPreservingPrimary
          (readFdToEnd maximumCapturedOutputBytes descriptor)
          (ignoreIOException (closeFd descriptor))
      )
  putMVar result readResult

collectTargetStreamEvidence ::
  MVar (Either SomeException ()) ->
  MVar (Either SomeException ByteString.ByteString) ->
  MVar (Either SomeException ByteString.ByteString) ->
  IO (InputEvidence, CaptureEvidence, CaptureEvidence)
collectTargetStreamEvidence inputResult stdoutResult stderrResult = do
  collectedInput <- takeMVarBounded "stdin writer" inputResult
  collectedStdout <- takeMVarBounded "stdout capture" stdoutResult
  collectedStderr <- takeMVarBounded "stderr capture" stderrResult
  let asynchronousFailures =
        concatMap
          collectedAsyncFailures
          [ voidNestedResult collectedInput,
            voidNestedResult collectedStdout,
            voidNestedResult collectedStderr
          ]
  case asynchronousFailures of
    [] ->
      pure
        ( inputEvidenceFromResult collectedInput,
          captureEvidenceFromResult "stdout" collectedStdout,
          captureEvidenceFromResult "stderr" collectedStderr
        )
    _ -> do
      runCleanupsPreservingFailures (map throwIO asynchronousFailures)
      ioError
        (userError "runBoundedCommand: target stream worker cancellation escaped")

voidNestedResult ::
  Either String (Either SomeException value) ->
  Either String (Either SomeException ())
voidNestedResult =
  fmap void

collectedAsyncFailures ::
  Either String (Either SomeException value) ->
  [SomeException]
collectedAsyncFailures collected =
  case collected of
    Left _ -> []
    Right result ->
      filter isAsynchronousException (exceptionFailures result)

inputEvidenceFromResult ::
  Either String (Either SomeException ()) ->
  InputEvidence
inputEvidenceFromResult result =
  case result of
    Left failure -> InputFailed failure
    Right (Left failure) -> InputFailed (displayException failure)
    Right (Right ()) -> InputCompleted

captureEvidenceFromResult ::
  String ->
  Either String (Either SomeException ByteString.ByteString) ->
  CaptureEvidence
captureEvidenceFromResult label result =
  case result of
    Left failure -> CaptureFailed failure
    Right (Left failure) ->
      CaptureFailed
        ( "runBoundedCommand: "
            <> label
            <> " capture failed: "
            <> displayException failure
        )
    Right (Right contents) -> CaptureCompleted contents

waitForTrackedProcessMaybe ::
  TrackedProcess ->
  IO (Maybe ProcessStatus)
waitForTrackedProcessMaybe tracked = do
  outcome <-
    Readiness.awaitReadiness
      (Readiness.pollLimitedDeadline 10000 1 1 101)
      pollTracked
  pure
    ( Readiness.foldReadiness
        Just
        (const Nothing)
        (const Nothing)
        outcome
    )
  where
    pollTracked = do
      maybeStatus <- pollTrackedProcess tracked
      pure
        ( maybe
            (Left (Readiness.Progress 0 1 "waiting for owned child exit"))
            Right
            maybeStatus
        )

readFdToEnd :: Int -> Fd -> IO ByteString.ByteString
readFdToEnd maximumBytes descriptor =
  go 0 [] False
  where
    go bytesRead chunks overflowed = do
      contents <- readFdChunk descriptor 32768
      if ByteString.null contents
        then
          if overflowed
            then
              ioError
                (userError "bounded-command capture exceeds its size limit")
            else pure (ByteString.concat (reverse chunks))
        else
          if overflowed || ByteString.length contents > maximumBytes - bytesRead
            then go bytesRead [] True
            else
              go
                (bytesRead + ByteString.length contents)
                (contents : chunks)
                False

readRegularFdPrefix :: Int -> Fd -> IO ByteString.ByteString
readRegularFdPrefix maximumBytes descriptor =
  go 0 []
  where
    go bytesRead chunks
      | bytesRead >= maximumBytes =
          pure (ByteString.concat (reverse chunks))
      | otherwise = do
          contents <-
            readRegularFdChunk
              descriptor
              (min 32768 (maximumBytes - bytesRead))
          if ByteString.null contents
            then pure (ByteString.concat (reverse chunks))
            else
              go
                (bytesRead + ByteString.length contents)
                (contents : chunks)

-- Activity documents have already been proven to be regular files. Darwin's
-- kqueue does not reliably wake a second `threadWaitRead` at regular-file EOF,
-- so read them directly and reserve the readiness wait for protocol pipes.
readRegularFdChunk :: Fd -> Int -> IO ByteString.ByteString
readRegularFdChunk descriptor requestedBytes = do
  result <-
    try @IOException
      (PosixByteString.fdRead descriptor (fromIntegral requestedBytes))
  case result of
    Left failure
      | ioeGetErrorType failure == EOF ->
          pure ByteString.empty
    Left failure
      | ioeGetErrorType failure == Interrupted ->
          readRegularFdChunk descriptor requestedBytes
      | otherwise -> ioError failure
    Right contents -> pure contents

readFdChunk :: Fd -> Int -> IO ByteString.ByteString
readFdChunk descriptor requestedBytes = do
  threadWaitRead descriptor
  result <-
    try @IOException
      (PosixByteString.fdRead descriptor (fromIntegral requestedBytes))
  case result of
    Left failure
      | ioeGetErrorType failure == EOF ->
          pure ByteString.empty
    Left failure
      | retryableDescriptorError failure ->
          readFdChunk descriptor requestedBytes
      | otherwise -> ioError failure
    Right contents -> pure contents

retryableDescriptorError :: IOException -> Bool
retryableDescriptorError failure =
  ioeGetErrorType failure `elem` [Interrupted, ResourceExhausted]
