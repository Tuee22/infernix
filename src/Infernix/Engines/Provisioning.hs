{-# LANGUAGE DataKinds #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE TypeApplications #-}

-- | Package-internal bounded provisioning facade. Every process operation is
-- selected from a closed semantic language and runs through
-- 'Infernix.Cluster.Subprocess.runBoundedCommand'. The rank-2 region prevents
-- the grant from escaping, while the hidden deadline constructor makes a
-- missing or non-positive total deadline unrepresentable at execution time.
module Infernix.Engines.Provisioning
  ( AppleAdapterId,
    llamaCppCliAdapter,
    whisperCppCliAdapter,
    ctranslate2Adapter,
    onnxRuntimeAdapter,
    mlxAdapter,
    coreMlAdapter,
    jvmAdapter,
    parseAppleAdapterId,
    renderAppleAdapterId,
    ApplePythonAdapterId,
    ctranslate2PythonAdapter,
    onnxRuntimePythonAdapter,
    mlxPythonAdapter,
    coreMlPythonAdapter,
    pythonAdapterForApple,
    renderApplePythonAdapterId,
    ApplePoetrySetupId,
    diffusersPoetrySetup,
    pytorchPoetrySetup,
    transformersPoetrySetup,
    vllmPoetrySetup,
    parseApplePoetrySetupId,
    parseApplePoetrySetupEntrypoint,
    renderApplePoetryAdapterId,
    renderApplePoetrySetupEntrypoint,
    PoetryInstallGroup,
    parsePoetryInstallGroup,
    renderPoetryInstallGroup,
    ProvisioningDeadline,
    mkProvisioningDeadline,
    provisioningDeadlineMicros,
    ProvisioningOutcome (..),
    LinuxNativeSmokePolicy (..),
    ProvisioningGrant,
    ProjectWriter,
    PoetryBootstrapWriter,
    GeneratedBindingsWriter,
    DownloadCacheWriter,
    EngineWriter,
    AudiverisDmgReceipt,
    StagedAudiverisDmg,
    ProvisioningSession,
    ResolvedPoetry,
    ResolvedProjectPython,
    ResolvedPython,
    CandidatePythonTarget,
    candidatePythonTargetAdapter,
    candidatePythonTargetRelativePath,
    PoetryBootstrapPython,
    ResolvedHostNativeCli,
    InstalledRuntimeSource,
    installedRuntimeSourcePath,
    installedRuntimeOwnedPath,
    installedRuntimeSourceDigest,
    installedRuntimeSourceFiles,
    installedRuntimeSourceBytes,
    InstalledMachORuntimeClosure,
    installedMachORuntimeClosureRoot,
    installedMachORuntimeClosureFiles,
    installedMachORuntimeClosureBytes,
    installedMachORuntimeClosureDigest,
    installedMachORuntimeClosureSources,
    MachOFixturePlan (..),
    inspectMachOFixtureForTest,
    resolveMachOPathsFixtureForTest,
    AppleRuntimeVersion,
    appleRuntimeVersionText,
    parseAppleRuntimeVersionForTest,
    AppleManifestBuilder,
    mkAppleManifestBuilder,
    LinuxManifestBuilder,
    mkLinuxManifestBuilder,
    resolvePoetry,
    resolveProjectPython,
    resolvePython,
    resolveHostNativeCli,
    materializeResolvedPythonRuntimeClosure,
    materializeResolvedHostNativeCli,
    materializeAudiverisRuntimeClosure,
    resolvedPythonAdapter,
    resolvedRunnerPythonIdentity,
    executableMutationDuringHashRejectedForTest,
    relocationCandidateByteBoundForTest,
    validateRelocationCandidateByteSequenceForTest,
    completeAppleCandidate,
    completeLinuxCandidate,
    withProvisioningGrant,
    withEngineProvisioningSession,
    withPythonProvisioningSession,
    withPoetryBootstrapProvisioningSession,
    withAppleProvisioningSession,
    appleProvisioningLockContentionForTest,
    bracketProvisioning,
    failProvisioningSession,
    pauseProvisioningSessionForTest,
    commitAfterInterruptibleProvisioning,
    provisioningPoetryProjectReady,
    provisioningPoetryBootstrapExecutable,
    provisioningGeneratedBindingsRequired,
    provisioningAppleSetupReady,
    provisioningPublishAppleSetupManifest,
    provisioningPublishAppleSetupManifestWithPauseForTest,
    provisioningLegacyAppleRuntimeBridgeInfo,
    provisioningAudiverisCandidateInfo,
    provisioningAudiverisMountInfo,
    provisioningAudiverisMountedAppPresent,
    provisioningReadAudiverisActivity,
    provisioningCopyAudiverisMountedApp,
    provisioningRetireAudiverisStaging,
    provisioningCreateDirectory,
    provisioningProjectCreateDirectory,
    provisioningCreateGeneratedBindingNamespaces,
    provisioningRemovePath,
    provisioningRenameFile,
    StableFileCopyEvidence,
    stableFileCopyDigest,
    stableFileCopyInfo,
    provisioningCopyFileStable,
    provisioningCopyFileStableBounded,
    provisioningInstallAppleNativeRunnerLibrary,
    provisioningListDynamicPayloads,
    provisioningReadAudiverisBundledJavaVersion,
    provisioningAudiverisDmgValid,
    provisioningAudiverisDownloadedDmgValid,
    validateAudiverisDmgReceipt,
    prepareAudiverisDmgDownload,
    promoteAudiverisDmgDownload,
    stageAudiverisDmgForCandidate,
    provisioningRelocateCandidateVenv,
    provisioningWriteFile,
    provisioningProjectWriteFile,
    provisioningWriteBytes,
    ProvisioningPathKind (..),
    ProvisioningPathInfo (..),
    DurableProvisioningRecord,
    provisioningPublishDurableRecord,
    provisioningRecoverDurableRecord,
    provisioningReplaceDurableRecord,
    provisioningRetireDurableRecord,
    ProvisioningProcessIdentity,
    provisioningCurrentProcessIdentity,
    provisioningProcessIdentityPid,
    provisioningProcessIdentityBirth,
    provisioningExactProcessIdentityAbsent,
    provisioningMakeExecutable,
    provisioningReconcileArtifactRoot,
    installPoetryProject,
    installPoetryProjectWithGroups,
    generatePythonProtoBindings,
    probePythonVersion,
    probePoetryBootstrapPython,
    createPythonVenv,
    materializeCandidatePythonTarget,
    createPoetryBootstrapVenv,
    materializePoetryBootstrapPython,
    installPinnedPoetryBootstrap,
    upgradePinnedPip,
    installPinnedRequirements,
    downloadAudiverisDmg,
    mountAudiverisDmg,
    detachAudiverisDmg,
    queryPythonVersion,
    queryPythonProvenance,
    pinnedPipRequirementSpec,
    pinnedPoetryBootstrapRequirementSpecs,
    pinnedPythonRequirementSpecs,
    audiverisPinnedVersion,
    audiverisPinnedDmgFileName,
    audiverisPinnedDmgUrl,
  )
where

import Control.Concurrent.MVar (MVar, putMVar, takeMVar)
import Control.Exception (IOException, displayException, mask, throwIO, try)
import Control.Monad (foldM, foldM_, unless, when, zipWithM)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types qualified as AesonTypes
import Data.Bits (shiftL, (.&.), (.|.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isDigit)
import Data.List qualified as List
import Data.Maybe (catMaybes, isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Time.Clock (UTCTime)
import Data.Word (Word32, Word64, Word8)
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (..))
import Infernix.Engines.Artifact qualified as Artifact
import Infernix.Engines.Artifact.Activation qualified as ArtifactActivation
import Infernix.Engines.Artifact.Identity qualified as ArtifactIdentity
import Infernix.Engines.Artifact.Internal qualified as ArtifactInternal
import Infernix.Engines.Artifact.Recipe qualified as Recipe
import Infernix.Engines.Artifact.Target
  ( NativeArtifactTarget,
    NativeArtifactTargetEvidence,
    nativeArtifactTarget,
    nativeArtifactTargetFingerprint,
  )
import Infernix.Engines.DownloadCacheLock.Internal
  ( DownloadCacheMutationAuthority,
    withDownloadCacheMutationLockInternal,
  )
import Infernix.Engines.MaterializationLock.Internal
  ( ArtifactGenerationLease,
    ArtifactGenerationMutationAuthority,
    MaterializationAuthority,
    artifactGenerationLease,
    artifactGenerationLeaseFields,
    reconcileObsoleteArtifactGenerationLeases,
    withEngineMaterializationLock,
    withTryArtifactGenerationMutationLock,
  )
import Infernix.Engines.Provisioning.Internal qualified as Internal
import Infernix.Error
  ( bracketPreservingPrimary,
    finallyPreservingPrimary,
    onExceptionPreservingPrimary,
  )
import Infernix.ProcessIdentity
  ( parseProcessBirthIdentity,
    readProcessBirthIdentity,
    registerCurrentProcessIdentity,
    renderProcessBirthIdentity,
  )
import Infernix.Python.MutationLock.Internal
  ( GeneratedBindingsMutationAuthority,
    PoetryBootstrapMutationAuthority,
    PoetryProjectMutationAuthority,
    withGeneratedBindingsMutationLockInternal,
    withPoetryBootstrapMutationLockInternal,
    withPoetryProjectMutationLockInternal,
  )
import System.Directory qualified as Directory
import System.Exit (ExitCode (ExitSuccess))
import System.FilePath
  ( isAbsolute,
    joinPath,
    makeRelative,
    normalise,
    splitDirectories,
    takeDirectory,
    takeExtension,
    takeFileName,
    (</>),
  )
import System.IO (SeekMode (AbsoluteSeek))
import System.IO.Error (isDoesNotExistError, isEOFError)
import System.Info qualified as SystemInfo
import System.Posix.Directory
  ( closeDirStream,
    readDirStream,
  )
import System.Posix.Directory.Fd
  ( unsafeOpenDirStreamFd,
  )
import System.Posix.Files qualified as Posix
import System.Posix.IO
  ( FdOption (CloseOnExec),
    OpenFileFlags (cloexec, creat, directory, exclusive, nofollow, nonBlock),
    OpenMode (ReadOnly, ReadWrite, WriteOnly),
    closeFd,
    defaultFileFlags,
    dup,
    fdSeek,
    openFd,
    openFdAt,
    setFdOption,
  )
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Process (getProcessID)
import System.Posix.Types (ByteCount, DeviceID, Fd, FileID, FileOffset)
import System.Posix.Unistd (fileSynchronise)

newtype AppleAdapterId
  = AppleAdapterId Internal.AppleAdapterId
  deriving (Eq)

instance Show AppleAdapterId where
  show = renderAppleAdapterId

llamaCppCliAdapter :: AppleAdapterId
llamaCppCliAdapter =
  AppleAdapterId Internal.LlamaCppCliAdapter

whisperCppCliAdapter :: AppleAdapterId
whisperCppCliAdapter =
  AppleAdapterId Internal.WhisperCppCliAdapter

ctranslate2Adapter :: AppleAdapterId
ctranslate2Adapter =
  AppleAdapterId Internal.CTranslate2Adapter

onnxRuntimeAdapter :: AppleAdapterId
onnxRuntimeAdapter =
  AppleAdapterId Internal.OnnxRuntimeAdapter

mlxAdapter :: AppleAdapterId
mlxAdapter =
  AppleAdapterId Internal.MlxAdapter

coreMlAdapter :: AppleAdapterId
coreMlAdapter =
  AppleAdapterId Internal.CoreMlAdapter

jvmAdapter :: AppleAdapterId
jvmAdapter =
  AppleAdapterId Internal.JvmAdapter

parseAppleAdapterId :: String -> Maybe AppleAdapterId
parseAppleAdapterId rawValue =
  case rawValue of
    "llama-cpp-cli" -> Just llamaCppCliAdapter
    "whisper-cpp-cli" -> Just whisperCppCliAdapter
    "ctranslate2-native" -> Just ctranslate2Adapter
    "onnx-runtime-native" -> Just onnxRuntimeAdapter
    "mlx-native" -> Just mlxAdapter
    "coreml-native" -> Just coreMlAdapter
    "jvm-native" -> Just jvmAdapter
    _ -> Nothing

renderAppleAdapterId :: AppleAdapterId -> String
renderAppleAdapterId (AppleAdapterId adapter) =
  Internal.appleAdapterSlug adapter

newtype ApplePythonAdapterId
  = ApplePythonAdapterId Internal.ApplePythonAdapterId
  deriving (Eq)

instance Show ApplePythonAdapterId where
  show = renderApplePythonAdapterId

ctranslate2PythonAdapter :: ApplePythonAdapterId
ctranslate2PythonAdapter =
  ApplePythonAdapterId Internal.CTranslate2PythonAdapter

onnxRuntimePythonAdapter :: ApplePythonAdapterId
onnxRuntimePythonAdapter =
  ApplePythonAdapterId Internal.OnnxRuntimePythonAdapter

mlxPythonAdapter :: ApplePythonAdapterId
mlxPythonAdapter =
  ApplePythonAdapterId Internal.MlxPythonAdapter

coreMlPythonAdapter :: ApplePythonAdapterId
coreMlPythonAdapter =
  ApplePythonAdapterId Internal.CoreMlPythonAdapter

pythonAdapterForApple :: AppleAdapterId -> Maybe ApplePythonAdapterId
pythonAdapterForApple (AppleAdapterId adapter) =
  case adapter of
    Internal.CTranslate2Adapter ->
      Just ctranslate2PythonAdapter
    Internal.OnnxRuntimeAdapter ->
      Just onnxRuntimePythonAdapter
    Internal.MlxAdapter ->
      Just mlxPythonAdapter
    Internal.CoreMlAdapter ->
      Just coreMlPythonAdapter
    Internal.LlamaCppCliAdapter -> Nothing
    Internal.WhisperCppCliAdapter -> Nothing
    Internal.JvmAdapter -> Nothing

renderApplePythonAdapterId :: ApplePythonAdapterId -> String
renderApplePythonAdapterId (ApplePythonAdapterId adapter) =
  Internal.applePythonAdapterSlug adapter

newtype ApplePoetrySetupId
  = ApplePoetrySetupId Internal.ApplePoetrySetupId
  deriving (Eq)

instance Show ApplePoetrySetupId where
  show = renderApplePoetryAdapterId

diffusersPoetrySetup :: ApplePoetrySetupId
diffusersPoetrySetup =
  ApplePoetrySetupId Internal.DiffusersPoetrySetup

pytorchPoetrySetup :: ApplePoetrySetupId
pytorchPoetrySetup =
  ApplePoetrySetupId Internal.PytorchPoetrySetup

transformersPoetrySetup :: ApplePoetrySetupId
transformersPoetrySetup =
  ApplePoetrySetupId Internal.TransformersPoetrySetup

vllmPoetrySetup :: ApplePoetrySetupId
vllmPoetrySetup =
  ApplePoetrySetupId Internal.VllmPoetrySetup

parseApplePoetrySetupId :: String -> Maybe ApplePoetrySetupId
parseApplePoetrySetupId rawValue =
  case rawValue of
    "diffusers-python" -> Just diffusersPoetrySetup
    "pytorch-python" -> Just pytorchPoetrySetup
    "transformers-python" -> Just transformersPoetrySetup
    "vllm-python" -> Just vllmPoetrySetup
    _ -> Nothing

parseApplePoetrySetupEntrypoint :: String -> Maybe ApplePoetrySetupId
parseApplePoetrySetupEntrypoint rawValue =
  case rawValue of
    "setup-diffusers-python" -> Just diffusersPoetrySetup
    "setup-pytorch-python" -> Just pytorchPoetrySetup
    "setup-transformers-python" -> Just transformersPoetrySetup
    "setup-vllm-python" -> Just vllmPoetrySetup
    _ -> Nothing

renderApplePoetryAdapterId :: ApplePoetrySetupId -> String
renderApplePoetryAdapterId (ApplePoetrySetupId setup) =
  Internal.applePoetryAdapterSlug setup

renderApplePoetrySetupEntrypoint :: ApplePoetrySetupId -> String
renderApplePoetrySetupEntrypoint (ApplePoetrySetupId setup) =
  Internal.applePoetrySetupEntrypoint setup

newtype PoetryInstallGroup
  = PoetryInstallGroup Internal.PoetryInstallGroup
  deriving (Eq, Ord)

instance Show PoetryInstallGroup where
  show = renderPoetryInstallGroup

parsePoetryInstallGroup :: String -> Maybe PoetryInstallGroup
parsePoetryInstallGroup value =
  PoetryInstallGroup
    <$> case value of
      "dev" -> Just Internal.PoetryDevGroup
      "cuda" -> Just Internal.PoetryCudaGroup
      "linux-cpu" -> Just Internal.PoetryLinuxCpuGroup
      "apple-silicon" -> Just Internal.PoetryAppleSiliconGroup
      _ -> Nothing

renderPoetryInstallGroup :: PoetryInstallGroup -> String
renderPoetryInstallGroup (PoetryInstallGroup group) =
  Internal.poetryInstallGroupSlug group

-- | A positive total deadline for exactly one provisioning operation.
newtype ProvisioningDeadline
  = ProvisioningDeadline Internal.PositiveProvisioningTimeout
  deriving (Eq, Show)

mkProvisioningDeadline :: Int -> Either String ProvisioningDeadline
mkProvisioningDeadline microseconds =
  ProvisioningDeadline
    <$> Internal.mkPositiveProvisioningTimeout microseconds

provisioningDeadlineMicros :: ProvisioningDeadline -> Int
provisioningDeadlineMicros (ProvisioningDeadline timeout) =
  Internal.positiveProvisioningTimeoutMicros timeout

-- | Exhaustive terminal classification for command validation and supervised
-- execution. Synchronous kernel failures remain distinct from a target's
-- genuine non-zero exit.
data ProvisioningOutcome
  = ProvisioningSucceeded !String
  | ProvisioningRejected !String
  | ProvisioningFailedFatal !String
  | ProvisioningFailedKernel !String
  | ProvisioningTimedOut !ProvisioningDeadline
  deriving (Eq, Show)

data LinuxNativeSmokePolicy
  = RequireImagePayload
  | AllowFixturePayloadAbsence
  deriving (Eq, Show)

-- | Region-scoped authority to run only the typed steps below.
newtype ProvisioningGrant s
  = ProvisioningGrant Subprocess.SubprocessEnv

type role ProvisioningGrant nominal

-- | Opaque evidence that the current continuation owns both the engine
-- materialization lock and this provisioning session. The extra rank-2
-- parameter prevents a writer lease from escaping the locked interpreter.
data EngineWriter w s q
  = EngineWriter
      !(MaterializationAuthority w)
      !Subprocess.AbandonedActivitiesRecovered
      !AuthorizedWriterRoot

type role EngineWriter nominal nominal nominal

data ProjectWriter p s q
  = ProjectWriter
      !(PoetryProjectMutationAuthority p)
      !AuthorizedWriterRoot

type role ProjectWriter nominal nominal nominal

data PoetryBootstrapWriter b s q
  = PoetryBootstrapWriter
      !(PoetryBootstrapMutationAuthority b)
      !AuthorizedWriterRoot
      !FilePath

type role PoetryBootstrapWriter nominal nominal nominal

data GeneratedBindingsWriter g s q
  = GeneratedBindingsWriter
      !(GeneratedBindingsMutationAuthority g)
      !AuthorizedWriterRoot
      !FilePath

type role GeneratedBindingsWriter nominal nominal nominal

data DownloadCacheWriter d s q
  = DownloadCacheWriter
      !(DownloadCacheMutationAuthority d)
      !AuthorizedWriterRoot

type role DownloadCacheWriter nominal nominal nominal

data AudiverisDmgReceipt d s q = AudiverisDmgReceipt
  { audiverisDmgReceiptStatus :: !Posix.FileStatus,
    audiverisDmgReceiptDigest :: !Text
  }

type role AudiverisDmgReceipt nominal nominal nominal

data StagedAudiverisDmg w s q = StagedAudiverisDmg
  { stagedAudiverisCandidateRoot :: !FilePath,
    stagedAudiverisDmgStatus :: !Posix.FileStatus,
    stagedAudiverisDmgDigest :: !Text
  }

type role StagedAudiverisDmg nominal nominal nominal

data AuthorizedWriterRoot = AuthorizedWriterRoot
  { authorizedWriterConfiguredRoot :: !FilePath,
    authorizedWriterCanonicalRoot :: !FilePath,
    authorizedWriterRootDescriptor :: !Fd,
    authorizedWriterRootStatus :: !Posix.FileStatus,
    authorizedWriterMutationRoot :: !Subprocess.ProvisioningMutationRoot,
    authorizedWriterEnvironment :: !Subprocess.SubprocessEnv
  }

-- | Proof that the grant's typed host manifest names an available Poetry
-- launcher. The exact configured launcher remains the executable authority;
-- its interpreter and package tree are retained only as immutable closure
-- evidence for the direct launcher invocation.
newtype ResolvedPoetry s
  = ResolvedPoetry
      ( ResolvedExecutableIdentity,
        [Internal.ProvisioningPackageClosureIdentity],
        [Internal.ProvisioningRuntimeLibraryIdentity]
      )

type role ResolvedPoetry nominal

-- | Exact direct-target authority for the locked shared Python project.
-- Poetry can mint this only after installation has published the in-project
-- virtual environment. The interpreter, package tree, and adapter source tree
-- are all included in the hidden executable identity.
newtype ResolvedProjectPython s
  = ResolvedProjectPython
      ( ResolvedExecutableIdentity,
        [Internal.ProvisioningPackageClosureIdentity],
        [Internal.ProvisioningRuntimeLibraryIdentity]
      )

type role ResolvedProjectPython nominal

-- | Proof that the grant's typed host manifest names the exact Python tool
-- required by one adapter. The adapter identity is retained in the
-- capability, so it cannot drift between probing, venv creation, and
-- provenance collection.
newtype ResolvedPython s
  = ResolvedPython
      (Internal.ApplePythonAdapterId, ResolvedExecutableIdentity)

type role ResolvedPython nominal

-- | Exact regular Python executable installed inside one mutable candidate.
-- Its constructor is hidden so package installation, provenance, and smoke
-- cannot fall back to a venv symlink or to the host interpreter.
data CandidatePythonTarget s = CandidatePythonTarget
  { candidatePythonTargetInternalAdapter :: !Internal.ApplePythonAdapterId,
    candidatePythonTargetRoot :: !FilePath,
    candidatePythonTargetIdentity :: !ResolvedExecutableIdentity
  }

type role CandidatePythonTarget nominal

candidatePythonTargetAdapter ::
  CandidatePythonTarget s ->
  ApplePythonAdapterId
candidatePythonTargetAdapter =
  ApplePythonAdapterId . candidatePythonTargetInternalAdapter

candidatePythonTargetRelativePath ::
  CandidatePythonTarget s ->
  FilePath
candidatePythonTargetRelativePath _ =
  Internal.fixedVenvPythonRelativePath

data PoetryBootstrapPython s = PoetryBootstrapPython
  { poetryBootstrapPythonRoot :: !FilePath,
    poetryBootstrapPythonIdentity :: !ResolvedExecutableIdentity
  }

type role PoetryBootstrapPython nominal

newtype ResolvedHostNativeCli s
  = ResolvedHostNativeCli
      (Internal.AppleAdapterId, ResolvedExecutableIdentity)

type role ResolvedHostNativeCli nominal

data ResolvedExecutableIdentity = ResolvedExecutableIdentity
  { resolvedExecutableConfiguredPath :: !FilePath,
    resolvedExecutableCanonicalPath :: !FilePath,
    resolvedExecutableConfiguredStatus :: !Posix.FileStatus,
    resolvedExecutableCanonicalStatus :: !Posix.FileStatus,
    resolvedExecutableDigest :: !Text
  }

data InstalledRuntimeSource = InstalledRuntimeSource
  { installedRuntimeSourcePath :: !FilePath,
    installedRuntimeOwnedPath :: !FilePath,
    installedRuntimeSourceDigest :: !Text,
    installedRuntimeSourceFiles :: !Integer,
    installedRuntimeSourceBytes :: !Integer
  }
  deriving (Eq, Show)

data InstalledMachORuntimeClosure s = InstalledMachORuntimeClosure
  { installedMachORuntimeClosureRoot :: !FilePath,
    installedMachORuntimeClosureFiles :: !Int,
    installedMachORuntimeClosureBytes :: !Integer,
    installedMachORuntimeClosureDigest :: !Text,
    installedMachORuntimeClosureSources :: ![InstalledRuntimeSource]
  }

type role InstalledMachORuntimeClosure nominal

newtype AppleRuntimeVersion
  = AppleRuntimeVersion Text
  deriving (Eq, Show)

appleRuntimeVersionText :: AppleRuntimeVersion -> Text
appleRuntimeVersionText (AppleRuntimeVersion version) =
  version

-- | Indexed provisioning program. Its constructor and interpreter are hidden,
-- so capturing a grant in an unrestricted 'IO' closure cannot execute a step
-- after the rank-2 region ends.
newtype ProvisioningSession s result
  = ProvisioningSession (IO result)

type role ProvisioningSession nominal representational

instance Functor (ProvisioningSession s) where
  fmap transform (ProvisioningSession action) =
    ProvisioningSession (transform <$> action)

instance Applicative (ProvisioningSession s) where
  pure = ProvisioningSession . pure
  ProvisioningSession transform <*> ProvisioningSession action =
    ProvisioningSession (transform <*> action)

instance Monad (ProvisioningSession s) where
  ProvisioningSession action >>= next =
    ProvisioningSession $ do
      value <- action
      case next value of
        ProvisioningSession nextAction -> nextAction

withProvisioningGrant ::
  Subprocess.SubprocessEnv ->
  (forall s. ProvisioningGrant s -> ProvisioningSession s result) ->
  IO result
withProvisioningGrant environment useGrant =
  case useGrant (ProvisioningGrant environment) of
    ProvisioningSession action -> action

withAuthorizedWriterRoot ::
  String ->
  FilePath ->
  Subprocess.SubprocessEnv ->
  (AuthorizedWriterRoot -> IO result) ->
  IO result
withAuthorizedWriterRoot label configuredRoot environment useRoot =
  mask $ \restore -> do
    unless
      (isAbsolute configuredRoot)
      (ioError (userError (label <> " writer root must be absolute")))
    canonicalRoot <- Directory.canonicalizePath configuredRoot
    listedStatus <- Posix.getSymbolicLinkStatus canonicalRoot
    unless
      ( Posix.isDirectory listedStatus
          && not (Posix.isSymbolicLink listedStatus)
      )
      (ioError (userError (label <> " writer root is not a real directory")))
    descriptor <-
      openFd
        canonicalRoot
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          openedStatus <- Posix.getFdStatus descriptor
          unless
            (sameFileObject listedStatus openedStatus)
            (ioError (userError (label <> " writer root changed before descriptor open")))
          mutationRootResult <-
            Subprocess.observeProvisioningMutationRoot
              (normalise canonicalRoot)
          mutationRoot <-
            case mutationRootResult of
              Left outcome ->
                ioError
                  ( userError
                      ( label
                          <> " writer mutation root observation failed: "
                          <> renderProvisioningMutationOutcome outcome
                      )
                  )
              Right observedRoot -> pure observedRoot
          useRoot
            AuthorizedWriterRoot
              { authorizedWriterConfiguredRoot =
                  normalise configuredRoot,
                authorizedWriterCanonicalRoot =
                  normalise canonicalRoot,
                authorizedWriterRootDescriptor = descriptor,
                authorizedWriterRootStatus = openedStatus,
                authorizedWriterMutationRoot = mutationRoot,
                authorizedWriterEnvironment = environment
              }
      )
      (closeFd descriptor)

withEngineProvisioningSession ::
  Paths ->
  FilePath ->
  Subprocess.SubprocessEnv ->
  ( forall w s q.
    EngineWriter w s q ->
    ProvisioningGrant s ->
    ProvisioningSession s result
  ) ->
  IO result
withEngineProvisioningSession paths enginesRoot environment build =
  withEngineMaterializationLock enginesRoot $ \authority ->
    do
      recovered <-
        Subprocess.recoverAbandonedBoundedCommandActivities paths
      withAuthorizedWriterRoot "engine" enginesRoot environment $ \authorizedRoot ->
        withProvisioningGrant environment $ \grant ->
          build
            (mintRecoveredEngineWriter authority recovered authorizedRoot)
            grant

withPythonProvisioningSession ::
  FilePath ->
  FilePath ->
  Subprocess.SubprocessEnv ->
  ( forall p g s q.
    ProjectWriter p s q ->
    GeneratedBindingsWriter g s q ->
    ProvisioningGrant s ->
    ProvisioningSession s result
  ) ->
  IO result
withPythonProvisioningSession
  repositoryRoot
  projectRoot
  environment
  build =
    withPoetryProjectMutationLockInternal projectRoot $ \projectAuthority ->
      withGeneratedBindingsMutationLockInternal repositoryRoot $ \bindingsAuthority ->
        withAuthorizedWriterRoot "project" projectRoot environment $ \projectAuthorizedRoot ->
          withAuthorizedWriterRoot "repository" repositoryRoot environment $ \repositoryAuthorizedRoot ->
            withProvisioningGrant environment $ \grant ->
              build
                (ProjectWriter projectAuthority projectAuthorizedRoot)
                ( GeneratedBindingsWriter
                    bindingsAuthority
                    repositoryAuthorizedRoot
                    ( authorizedWriterCanonicalRoot repositoryAuthorizedRoot
                        </> "tools"
                        </> "generated_proto"
                    )
                )
                grant

withPoetryBootstrapProvisioningSession ::
  FilePath ->
  Subprocess.SubprocessEnv ->
  ( forall b s q.
    PoetryBootstrapWriter b s q ->
    ProvisioningGrant s ->
    ProvisioningSession s result
  ) ->
  IO result
withPoetryBootstrapProvisioningSession
  homeDirectory
  environment
  build =
    withPoetryBootstrapMutationLockInternal homeDirectory $ \authority ->
      withAuthorizedWriterRoot "Poetry bootstrap home" homeDirectory environment $ \authorizedHome -> do
        let poetryHome =
              authorizedWriterCanonicalRoot authorizedHome
                </> ".local"
                </> "share"
                </> "pypoetry"
        ensureAuthorizedDirectoryTree
          "fixed Poetry bootstrap home"
          authorizedHome
          poetryHome
        withProvisioningGrant environment $ \grant ->
          build
            (PoetryBootstrapWriter authority authorizedHome poetryHome)
            grant

withAppleProvisioningSession ::
  Paths ->
  FilePath ->
  Subprocess.SubprocessEnv ->
  ( forall p g d w s q.
    ProjectWriter p s q ->
    GeneratedBindingsWriter g s q ->
    DownloadCacheWriter d s q ->
    EngineWriter w s q ->
    ProvisioningGrant s ->
    ProvisioningSession s result
  ) ->
  IO result
withAppleProvisioningSession
  paths
  projectRoot
  environment
  build =
    withPoetryProjectMutationLockInternal projectRoot $ \projectAuthority ->
      withGeneratedBindingsMutationLockInternal repositoryRoot $ \bindingsAuthority ->
        withDownloadCacheMutationLockInternal dataRootPath $ \cacheAuthority ->
          withEngineMaterializationLock enginesRoot $ \engineAuthority -> do
            recovered <-
              Subprocess.recoverAbandonedBoundedCommandActivities paths
            withAuthorizedWriterRoot "project" projectRoot environment $ \projectAuthorizedRoot ->
              withAuthorizedWriterRoot "repository" repositoryRoot environment $ \repositoryAuthorizedRoot ->
                withAuthorizedWriterRoot "data" dataRootPath environment $ \dataAuthorizedRoot -> do
                  ensureAuthorizedDirectoryTree
                    "download cache hierarchy"
                    dataAuthorizedRoot
                    downloadCacheRoot
                  withAuthorizedWriterRoot "download cache" downloadCacheRoot environment $ \cacheAuthorizedRoot ->
                    withAuthorizedWriterRoot "engine" enginesRoot environment $ \engineAuthorizedRoot ->
                      withProvisioningGrant environment $ \grant ->
                        build
                          (ProjectWriter projectAuthority projectAuthorizedRoot)
                          ( GeneratedBindingsWriter
                              bindingsAuthority
                              repositoryAuthorizedRoot
                              ( authorizedWriterCanonicalRoot repositoryAuthorizedRoot
                                  </> "tools"
                                  </> "generated_proto"
                              )
                          )
                          (DownloadCacheWriter cacheAuthority cacheAuthorizedRoot)
                          ( mintRecoveredEngineWriter
                              engineAuthority
                              recovered
                              engineAuthorizedRoot
                          )
                          grant
    where
      repositoryRoot = repoRoot paths
      dataRootPath = dataRoot paths
      enginesRoot = dataRootPath </> "engines"
      downloadCacheRoot =
        normalise dataRootPath </> "downloads" </> "engines"

appleProvisioningLockContentionForTest ::
  Paths ->
  FilePath ->
  Subprocess.SubprocessEnv ->
  IO (Bool, Bool, Bool, Bool)
appleProvisioningLockContentionForTest
  paths
  projectRoot
  environment =
    withAppleProvisioningSession
      paths
      projectRoot
      environment
      ( \_projectWriter _bindingsWriter _cacheWriter _engineWriter _grant ->
          ProvisioningSession $ do
            projectContended <-
              lockContentionResult
                ( withPoetryProjectMutationLockInternal
                    projectRoot
                    (const (pure ()))
                )
            bindingsContended <-
              lockContentionResult
                ( withGeneratedBindingsMutationLockInternal
                    (repoRoot paths)
                    (const (pure ()))
                )
            cacheContended <-
              lockContentionResult
                ( withDownloadCacheMutationLockInternal
                    dataRootPath
                    (const (pure ()))
                )
            engineContended <-
              lockContentionResult
                ( withEngineMaterializationLock
                    enginesRoot
                    (const (pure ()))
                )
            pure
              ( projectContended,
                bindingsContended,
                cacheContended,
                engineContended
              )
      )
    where
      dataRootPath = dataRoot paths
      enginesRoot = dataRootPath </> "engines"

mintRecoveredEngineWriter ::
  MaterializationAuthority w ->
  Subprocess.AbandonedActivitiesRecovered ->
  AuthorizedWriterRoot ->
  EngineWriter w s q
mintRecoveredEngineWriter =
  EngineWriter

lockContentionResult :: IO () -> IO Bool
lockContentionResult action = do
  result <- try @IOException action
  case result of
    Right () -> pure False
    Left failure
      | "lock is already held:"
          `List.isInfixOf` displayException failure ->
          pure True
      | otherwise -> throwIO failure

resolvePoetry ::
  ProvisioningGrant s ->
  ProvisioningSession s (Either String (ResolvedPoetry s))
resolvePoetry (ProvisioningGrant environment) =
  ProvisioningSession $ do
    case Subprocess.resolveProvisioningPoetry environment of
      Left failure -> pure (Left failure)
      Right poetryLauncherPath -> do
        launcherResolution <-
          resolveExecutableIdentity poetryLauncherPath
        case launcherResolution of
          Left failure -> pure (Left failure)
          Right launcherIdentity -> do
            interpreterResolution <-
              resolvePoetryInterpreter launcherIdentity
            case interpreterResolution of
              Left failure -> pure (Left failure)
              Right interpreterPath -> do
                identityResolution <-
                  resolveExecutableIdentity interpreterPath
                case identityResolution of
                  Left failure -> pure (Left failure)
                  Right interpreterIdentity -> do
                    closureResolution <-
                      resolvePoetryPackageClosure interpreterPath
                    case closureResolution of
                      Left failure -> pure (Left failure)
                      Right closureIdentities -> do
                        runtimeResolution <-
                          resolvePoetryRuntimeLibraries
                            interpreterIdentity
                            closureIdentities
                        pure
                          ( fmap
                              ( \runtimeLibraries ->
                                  ResolvedPoetry
                                    ( launcherIdentity,
                                      closureIdentities,
                                      runtimeLibraries
                                    )
                              )
                              runtimeResolution
                          )

resolveProjectPython ::
  ProjectWriter p s q ->
  ProvisioningSession s (Either String (ResolvedProjectPython s))
resolveProjectPython (ProjectWriter _ projectRoot) =
  ProvisioningSession $ do
    let projectDirectory =
          authorizedWriterCanonicalRoot projectRoot
        projectPython =
          projectDirectory </> ".venv" </> "bin" </> "python"
        projectSource =
          projectDirectory </> "adapters"
    validation <-
      try @IOException $ do
        validateWriterRootIdentity
          "direct project Python resolution"
          projectRoot
        identity <- resolveExactExecutableIdentity projectPython
        sitePackagesRoot <- resolvePoetrySitePackagesRoot projectPython
        unless
          ( writerPathWithin
              (projectDirectory </> ".venv")
              sitePackagesRoot
          )
          (ioError (userError "project Python site-packages escaped its locked venv"))
        let pythonHomeRoot =
              takeDirectory
                (takeDirectory (resolvedExecutableCanonicalPath identity))
        pythonHome <-
          resolvePackageClosureIdentity
            Internal.ProvisioningPythonHomeClosure
            pythonHomeRoot
        sitePackages <-
          resolvePackageClosureIdentity
            Internal.ProvisioningPythonPathClosure
            sitePackagesRoot
        sourceClosure <-
          resolvePackageClosureIdentity
            Internal.ProvisioningProjectSourceClosure
            projectSource
        let closures = [pythonHome, sitePackages, sourceClosure]
            closureBytes =
              sum
                (map Internal.provisioningPackageClosureBytes closures)
            closureFiles =
              sum
                (map Internal.provisioningPackageClosureFiles closures)
        unless
          ( closureBytes <= maximumPoetryClosureBytes
              && closureFiles <= maximumPoetryClosureFiles
          )
          (ioError (userError "direct project Python closure exceeds its fixed bound"))
        runtimeLibrariesResult <-
          resolvePoetryRuntimeLibraries identity closures
        runtimeLibraries <-
          either (ioError . userError) pure runtimeLibrariesResult
        finalIdentity <- resolveExactExecutableIdentity projectPython
        finalSource <-
          resolvePackageClosureIdentity
            Internal.ProvisioningProjectSourceClosure
            projectSource
        validateWriterRootIdentity
          "direct project Python resolution"
          projectRoot
        unless
          ( resolvedExecutableIdentityMatches identity finalIdentity
              && sourceClosure == finalSource
          )
          (ioError (userError "direct project Python authority changed while minted"))
        pure
          ( ResolvedProjectPython
              (identity, closures, runtimeLibraries)
          )
    pure
      ( case validation of
          Left failure -> Left (displayException failure)
          Right resolved -> Right resolved
      )

resolvePython ::
  ProvisioningGrant s ->
  ApplePythonAdapterId ->
  ProvisioningSession s (Either String (ResolvedPython s))
resolvePython
  (ProvisioningGrant environment)
  (ApplePythonAdapterId adapter) =
    ProvisioningSession $
      case Subprocess.resolveProvisioningPython adapter environment of
        Left failure -> pure (Left failure)
        Right executablePath ->
          fmap
            (\identity -> ResolvedPython (adapter, identity))
            <$> resolveExecutableIdentity executablePath

resolvedPythonAdapter :: ResolvedPython s -> ApplePythonAdapterId
resolvedPythonAdapter (ResolvedPython (adapter, _)) =
  ApplePythonAdapterId adapter

resolveHostNativeCli ::
  ProvisioningGrant s ->
  AppleAdapterId ->
  ProvisioningSession s (Either String (ResolvedHostNativeCli s))
resolveHostNativeCli
  (ProvisioningGrant environment)
  (AppleAdapterId adapter) =
    ProvisioningSession $
      case Subprocess.resolveProvisioningHostNativeCli adapter environment of
        Left failure -> pure (Left failure)
        Right executablePath ->
          fmap
            (\identity -> ResolvedHostNativeCli (adapter, identity))
            <$> resolveExecutableIdentity executablePath

materializeResolvedPythonRuntimeClosure ::
  EngineWriter w s q ->
  ResolvedPython s ->
  CandidatePythonTarget s ->
  FilePath ->
  ProvisioningSession s (InstalledMachORuntimeClosure s)
materializeResolvedPythonRuntimeClosure
  writer
  (ResolvedPython (adapter, pythonIdentity))
  target
  candidateRoot = do
    requireCandidatePythonTarget
      adapter
      candidateRoot
      target
    ownedCandidate <-
      authorizeEnginePath
        "Python runtime candidate root"
        writer
        candidateRoot
    sourcePythonHome <-
      case resolvedPythonFrameworkHome pythonIdentity of
        Left failure -> failProvisioningSession failure
        Right home -> pure home
    let installedPythonHome = ownedCandidate </> "python-home"
        candidateVenv = ownedCandidate </> "venv"
    sourceHomeIdentity <-
      ProvisioningSession
        ( resolvePackageClosureIdentity
            Internal.ProvisioningPythonHomeClosure
            sourcePythonHome
        )
    candidateVenvIdentity <-
      ProvisioningSession
        ( resolvePackageClosureIdentity
            Internal.ProvisioningArtifactRootClosure
            candidateVenv
        )
    runtimeLibraries <-
      resolveExactMachORuntimeLibraries
        pythonIdentity
        [candidateVenvIdentity]
    homeSource <-
      copyExactPackageClosure
        writer
        sourceHomeIdentity
        installedPythonHome
    frameworkSources <-
      materializePythonFrameworkLinks
        writer
        ownedCandidate
        sourcePythonHome
        installedPythonHome
    librarySources <-
      materializeRuntimeLibraries
        writer
        ownedCandidate
        [sourcePythonHome, candidateVenv]
        runtimeLibraries
    installedRuntimeEvidence
      ownedCandidate
      (homeSource : frameworkSources <> librarySources)

materializeResolvedHostNativeCli ::
  EngineWriter w s q ->
  ResolvedHostNativeCli s ->
  FilePath ->
  ProvisioningSession s (InstalledMachORuntimeClosure s)
materializeResolvedHostNativeCli
  writer
  (ResolvedHostNativeCli (adapter, cliIdentity))
  candidateRoot = do
    ownedCandidate <-
      authorizeEnginePath
        "host native CLI candidate root"
        writer
        candidateRoot
    cliName <-
      case adapter of
        Internal.LlamaCppCliAdapter -> pure "llama-cli"
        Internal.WhisperCppCliAdapter -> pure "whisper-cli"
        _ ->
          failProvisioningSession
            "resolved host native CLI capability has an unsupported adapter"
    baseRuntimeLibraries <-
      resolveExactMachORuntimeLibraries cliIdentity []
    pluginRoots <-
      ProvisioningSession
        ( discoverGgmlPluginRoots
            ( resolvedExecutableCanonicalPath cliIdentity
                : concatMap
                  ( \library ->
                      [ Internal.provisioningRuntimeLibraryConfiguredPath library,
                        Internal.provisioningRuntimeLibraryCanonicalPath library
                      ]
                  )
                  baseRuntimeLibraries
            )
        )
    unless
      (length pluginRoots <= 1)
      ( failProvisioningSession
          "host native CLI resolved more than one exact ggml libexec closure"
      )
    pluginIdentities <-
      ProvisioningSession
        ( mapM
            ( resolvePackageClosureIdentity
                Internal.ProvisioningArtifactRootClosure
            )
            pluginRoots
        )
    runtimeLibraries <-
      resolveExactMachORuntimeLibraries cliIdentity pluginIdentities
    let installedCli =
          ownedCandidate
            </> "native"
            </> "bin"
            </> cliName
    cliSource <-
      copyResolvedExecutableFile
        writer
        ownedCandidate
        cliIdentity
        installedCli
    pluginSources <-
      case pluginIdentities of
        [] -> pure []
        [pluginIdentity] ->
          (: [])
            <$> copyExactPackageClosure
              writer
              pluginIdentity
              (ownedCandidate </> "native" </> "libexec")
        _ ->
          failProvisioningSession
            "host native CLI plugin closure cardinality changed"
    librarySources <-
      materializeRuntimeLibraries
        writer
        ownedCandidate
        (ownedCandidate : pluginRoots)
        runtimeLibraries
    installedRuntimeEvidence
      ownedCandidate
      (cliSource : pluginSources <> librarySources)

materializeAudiverisRuntimeClosure ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s (InstalledMachORuntimeClosure s)
materializeAudiverisRuntimeClosure writer candidateRoot = do
  ownedCandidate <-
    authorizeEnginePath
      "Audiveris runtime candidate root"
      writer
      candidateRoot
  let appRoot = ownedCandidate </> "Audiveris.app"
      launcher =
        appRoot
          </> "Contents"
          </> "MacOS"
          </> "Audiveris"
  authorizedApp <-
    authorizeEnginePath "Audiveris fixed application root" writer appRoot
  authorizedLauncher <-
    authorizeEnginePath "Audiveris fixed launcher" writer launcher
  launcherIdentity <-
    ProvisioningSession (resolveExactExecutableIdentity authorizedLauncher)
  unless
    ( executableIdentityHasExecuteBit launcherIdentity
        && writerPathWithin authorizedApp authorizedLauncher
    )
    (failProvisioningSession "Audiveris fixed launcher is not an executable app descendant")
  appIdentity <-
    ProvisioningSession
      ( resolvePackageClosureIdentity
          Internal.ProvisioningArtifactRootClosure
          authorizedApp
      )
  appImages <-
    ProvisioningSession (scanPackageClosureMachOFiles appIdentity)
  seedImage <-
    case appImages of
      [] ->
        failProvisioningSession
          "Audiveris exact app closure contains no Mach-O runtime image"
      image : _ -> pure image
  seedIdentity <-
    ProvisioningSession
      ( resolveExactExecutableIdentity
          (Internal.provisioningRuntimeLibraryCanonicalPath seedImage)
      )
  unless
    (resolvedIdentityMatchesRuntimeIdentity seedIdentity seedImage)
    (failProvisioningSession "Audiveris Mach-O seed identity changed")
  appRuntimeLibraries <-
    resolveExactMachORuntimeLibraries seedIdentity [appIdentity]
  unless
    ( all
        ( writerPathWithin authorizedApp
            . Internal.provisioningRuntimeLibraryCanonicalPath
        )
        appRuntimeLibraries
    )
    ( failProvisioningSession
        "Audiveris has a non-system Mach-O dependency outside its exact app closure"
    )
  installedRuntimeEvidence
    ownedCandidate
    [ InstalledRuntimeSource
        { installedRuntimeSourcePath = authorizedApp,
          installedRuntimeOwnedPath = authorizedApp,
          installedRuntimeSourceDigest =
            Internal.provisioningPackageClosureDigest appIdentity,
          installedRuntimeSourceFiles =
            Internal.provisioningPackageClosureFiles appIdentity,
          installedRuntimeSourceBytes =
            Internal.provisioningPackageClosureBytes appIdentity
        }
    ]

resolveExactMachORuntimeLibraries ::
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  ProvisioningSession s [Internal.ProvisioningRuntimeLibraryIdentity]
resolveExactMachORuntimeLibraries identity packageClosures =
  ProvisioningSession $ do
    observed <- resolveExactExecutableIdentity (resolvedExecutableCanonicalPath identity)
    unless
      (resolvedExecutableIdentityMatches identity observed)
      (ioError (userError "resolved Mach-O executable changed before closure resolution"))
    resolution <-
      resolvePoetryRuntimeLibraries identity packageClosures
    case resolution of
      Left failure -> ioError (userError failure)
      Right libraries -> do
        finalObserved <-
          resolveExactExecutableIdentity
            (resolvedExecutableCanonicalPath identity)
        unless
          (resolvedExecutableIdentityMatches identity finalObserved)
          (ioError (userError "resolved Mach-O executable changed during closure resolution"))
        pure libraries

resolvedExecutableIdentityMatches ::
  ResolvedExecutableIdentity ->
  ResolvedExecutableIdentity ->
  Bool
resolvedExecutableIdentityMatches expected observed =
  normalise (resolvedExecutableConfiguredPath expected)
    == normalise (resolvedExecutableConfiguredPath observed)
    && normalise (resolvedExecutableCanonicalPath expected)
      == normalise (resolvedExecutableCanonicalPath observed)
    && stableExecutableStatus
      (resolvedExecutableConfiguredStatus expected)
      (resolvedExecutableConfiguredStatus observed)
    && stableExecutableStatus
      (resolvedExecutableCanonicalStatus expected)
      (resolvedExecutableCanonicalStatus observed)
    && resolvedExecutableDigest expected
      == resolvedExecutableDigest observed

executableIdentityHasExecuteBit :: ResolvedExecutableIdentity -> Bool
executableIdentityHasExecuteBit identity =
  Posix.fileMode (resolvedExecutableCanonicalStatus identity)
    .&. ( Posix.ownerExecuteMode
            .|. Posix.groupExecuteMode
            .|. Posix.otherExecuteMode
        )
    /= 0

resolvedPythonFrameworkHome ::
  ResolvedExecutableIdentity ->
  Either String FilePath
resolvedPythonFrameworkHome identity =
  locate [] (splitDirectories canonicalPath)
  where
    canonicalPath =
      normalise (resolvedExecutableCanonicalPath identity)

    locate prefix components =
      case components of
        ["Python.framework", "Versions", version, "bin", executable]
          | validFixedPathComponent version
              && validFixedPathComponent executable ->
              Right
                ( joinPath
                    (prefix <> ["Python.framework", "Versions", version])
                )
        component : remaining ->
          locate (prefix <> [component]) remaining
        [] ->
          Left
            ( "resolved Python is not inside the fixed Python.framework version layout: "
                <> canonicalPath
            )

resolveExecutableIdentity ::
  FilePath ->
  IO (Either String ResolvedExecutableIdentity)
resolveExecutableIdentity configuredPath = do
  result <-
    try @IOException $ do
      configuredStatus <- Posix.getSymbolicLinkStatus configuredPath
      canonicalPath <- Directory.canonicalizePath configuredPath
      canonicalStatus <- Posix.getSymbolicLinkStatus canonicalPath
      if
        | not (Posix.isRegularFile canonicalStatus) ->
            ioError
              (userError ("resolved executable is not a regular file: " <> canonicalPath))
        | Posix.isSymbolicLink canonicalStatus ->
            ioError
              (userError ("canonical executable remained a symbolic link: " <> canonicalPath))
        | fromIntegral (Posix.fileSize canonicalStatus)
            > maximumExactRuntimeFileBytes ->
            ioError
              (userError ("resolved executable exceeds its fixed size bound: " <> canonicalPath))
        | otherwise -> do
            (stableCanonicalStatus, digest) <-
              digestExecutable canonicalPath canonicalStatus
            pure
              ResolvedExecutableIdentity
                { resolvedExecutableConfiguredPath = configuredPath,
                  resolvedExecutableCanonicalPath = canonicalPath,
                  resolvedExecutableConfiguredStatus = configuredStatus,
                  resolvedExecutableCanonicalStatus = stableCanonicalStatus,
                  resolvedExecutableDigest = digest
                }
  pure
    ( case result of
        Left failure -> Left (displayException failure)
        Right identity -> Right identity
    )

resolvePoetryInterpreter ::
  ResolvedExecutableIdentity ->
  IO (Either String FilePath)
resolvePoetryInterpreter launcherIdentity = do
  result <-
    try @IOException $ do
      contents <- readExecutablePrefix launcherIdentity 4096
      let firstLine = ByteString.takeWhile (/= 10) contents
      line <-
        either
          (ioError . userError . ("Poetry launcher shebang is not UTF-8: " <>) . show)
          pure
          (TextEncoding.decodeUtf8' firstLine)
      shebang <-
        maybe
          (ioError (userError "Poetry launcher has no shebang"))
          pure
          (Text.stripPrefix "#!" line)
      case words (Text.unpack (Text.strip shebang)) of
        [interpreterPath]
          | isAbsolute interpreterPath ->
              pure interpreterPath
        _ ->
          ioError
            ( userError
                "Poetry launcher shebang must name one absolute interpreter"
            )
  pure (either (Left . displayException) Right result)

readExecutablePrefix ::
  ResolvedExecutableIdentity ->
  ByteCount ->
  IO ByteString.ByteString
readExecutablePrefix identity maximumBytes =
  mask $ \restore -> do
    let path = resolvedExecutableCanonicalPath identity
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
          openedStatus <- Posix.getFdStatus descriptor
          unless
            ( stableExecutableStatus
                (resolvedExecutableCanonicalStatus identity)
                openedStatus
            )
            (ioError (userError "Poetry launcher changed before shebang inspection"))
          contents <- PosixByteString.fdRead descriptor maximumBytes
          finalDescriptorStatus <- Posix.getFdStatus descriptor
          finalPathStatus <- Posix.getSymbolicLinkStatus path
          unless
            ( stableExecutableStatus openedStatus finalDescriptorStatus
                && stableExecutableStatus finalDescriptorStatus finalPathStatus
            )
            (ioError (userError "Poetry launcher changed during shebang inspection"))
          pure contents
      )
      (closeFd descriptor)

resolvePoetryPackageClosure ::
  FilePath ->
  IO (Either String [Internal.ProvisioningPackageClosureIdentity])
resolvePoetryPackageClosure interpreterPath = do
  result <-
    try @IOException $ do
      sitePackagesRoot <- resolvePoetrySitePackagesRoot interpreterPath
      pythonExecutable <- Directory.canonicalizePath interpreterPath
      let pythonHomeRoot =
            takeDirectory (takeDirectory pythonExecutable)
      pthRoots <- readPoetryPthRoots sitePackagesRoot
      pythonHome <-
        resolvePackageClosureIdentity
          Internal.ProvisioningPythonHomeClosure
          pythonHomeRoot
      pythonPaths <-
        mapM
          ( resolvePackageClosureIdentity
              Internal.ProvisioningPythonPathClosure
          )
          (List.nub (List.sort (sitePackagesRoot : pthRoots)))
      let closures = pythonHome : pythonPaths
          totalBytes =
            sum
              ( map
                  Internal.provisioningPackageClosureBytes
                  closures
              )
          totalFiles =
            sum
              ( map
                  Internal.provisioningPackageClosureFiles
                  closures
              )
      unless
        ( length closures <= maximumPoetryClosureCount
            && length
              ( List.nub
                  ( map
                      (normalise . Internal.provisioningPackageClosureRoot)
                      closures
                  )
              )
              == length closures
            && totalBytes <= maximumPoetryClosureBytes
            && totalFiles <= maximumPoetryClosureFiles
        )
        (ioError (userError "complete Poetry runtime closure exceeds its fixed bound"))
      pure closures
  pure (either (Left . displayException) Right result)

data MachOInspection = MachOInspection
  { machODependencies :: ![FilePath],
    machORpaths :: ![FilePath],
    machOMetadataBytes :: !Integer
  }
  deriving (Eq, Show)

data MachOQueueEntry = MachOQueueEntry
  { machOQueuePath :: !FilePath,
    machOQueueInheritedRpaths :: ![FilePath],
    machOQueueExpectedIdentity ::
      !Internal.ProvisioningRuntimeLibraryIdentity
  }
  deriving (Eq, Show)

data MachOClosureState = MachOClosureState
  { machOVisitedContexts :: ![(FilePath, [FilePath])],
    machOInspections ::
      ![(FilePath, ResolvedExecutableIdentity, MachOInspection)],
    machORuntimeLibraries ::
      ![Internal.ProvisioningRuntimeLibraryIdentity],
    machOEdgesObserved :: !Integer,
    machOBytesInspected :: !Integer,
    machOMetadataObserved :: !Integer
  }

data MachOFixturePlan = MachOFixturePlan
  { machOFixturePlannedCopies :: ![(FilePath, FilePath)],
    machOFixtureImageCount :: !Int,
    machOFixtureByteCount :: !Integer,
    machOFixtureContextCount :: !Int,
    machOFixtureEdgeCount :: !Integer,
    machOFixturePluginRootCount :: !Int
  }
  deriving (Eq, Show)

maximumMachOImages :: Int
maximumMachOImages = 1024

maximumMachOContexts :: Int
maximumMachOContexts = 2048

maximumMachOEdges :: Integer
maximumMachOEdges = 8192

maximumMachORpathsPerImage :: Int
maximumMachORpathsPerImage = 64

maximumMachORpathStack :: Int
maximumMachORpathStack = 128

maximumMachORuntimeLibraries :: Int
maximumMachORuntimeLibraries = 512

maximumMachORuntimeBytes :: Integer
maximumMachORuntimeBytes = 256 * 1024 * 1024

maximumMachOInspectionBytes :: Integer
maximumMachOInspectionBytes = 768 * 1024 * 1024

maximumMachOMetadataBytes :: Integer
maximumMachOMetadataBytes = 4 * 1024 * 1024

maximumMachOLoadCommands :: Word32
maximumMachOLoadCommands = 4096

maximumMachOLoadCommandBytes :: Word32
maximumMachOLoadCommandBytes = 4 * 1024 * 1024

maximumExactRuntimeFileBytes :: Integer
maximumExactRuntimeFileBytes = 128 * 1024 * 1024

resolvePoetryRuntimeLibraries ::
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  IO (Either String [Internal.ProvisioningRuntimeLibraryIdentity])
resolvePoetryRuntimeLibraries interpreterIdentity packageClosures = do
  result <-
    try @IOException $ do
      closureMachOIdentities <-
        concat
          <$> mapM scanPackageClosureMachOFiles packageClosures
      interpreterInspection <-
        inspectExactMachOImage interpreterIdentity
      let executableDirectory =
            takeDirectory
              (resolvedExecutableCanonicalPath interpreterIdentity)
      executableRpaths <-
        requireMachOResolution
          ( expandMachORpathStack
              (resolvedExecutableCanonicalPath interpreterIdentity)
              executableDirectory
              []
              (machORpaths interpreterInspection)
          )
      initialDependencies <-
        resolveMachODependencies
          (resolvedExecutableCanonicalPath interpreterIdentity)
          executableDirectory
          executableRpaths
          (machODependencies interpreterInspection)
      initialLibraries <-
        mapM
          (uncurry resolveRuntimeLibraryIdentity)
          initialDependencies
      initialRuntimeLibraries <-
        foldM insertRuntimeLibrary [] initialLibraries
      let initialBytes =
            fromIntegral
              ( Posix.fileSize
                  (resolvedExecutableCanonicalStatus interpreterIdentity)
              )
          initialMetadata =
            machOMetadataBytes interpreterInspection
          initialEdges =
            fromIntegral
              (length (machODependencies interpreterInspection))
          initialState =
            MachOClosureState
              { machOVisitedContexts =
                  [ ( resolvedExecutableCanonicalPath interpreterIdentity,
                      []
                    )
                  ],
                machOInspections =
                  [ ( resolvedExecutableCanonicalPath interpreterIdentity,
                      interpreterIdentity,
                      interpreterInspection
                    )
                  ],
                machORuntimeLibraries =
                  initialRuntimeLibraries,
                machOEdgesObserved = initialEdges,
                machOBytesInspected = initialBytes,
                machOMetadataObserved = initialMetadata
              }
          initialQueue =
            List.sortOn
              machOQueuePath
              ( [ MachOQueueEntry
                    (Internal.provisioningRuntimeLibraryConfiguredPath library)
                    executableRpaths
                    library
                | library <-
                    deduplicateRuntimeIdentitySources
                      (initialRuntimeLibraries <> closureMachOIdentities),
                  normalise
                    (Internal.provisioningRuntimeLibraryConfiguredPath library)
                    /= normalise
                      (resolvedExecutableCanonicalPath interpreterIdentity)
                ]
              )
      finalState <-
        walkMachOClosure
          executableDirectory
          initialState
          initialQueue
      validateMachOClosureState finalState
      pure
        ( List.sortOn
            Internal.provisioningRuntimeLibraryLeafName
            (machORuntimeLibraries finalState)
        )
  pure (either (Left . displayException) Right result)

walkMachOClosure ::
  FilePath ->
  MachOClosureState ->
  [MachOQueueEntry] ->
  IO MachOClosureState
walkMachOClosure executableDirectory state queue =
  case queue of
    [] -> pure state
    entry : remaining -> do
      identity <-
        resolveExactExecutableIdentity
          (machOQueuePath entry)
      unless
        ( resolvedIdentityMatchesRuntimeIdentity
            identity
            (machOQueueExpectedIdentity entry)
        )
        (ioError (userError "Mach-O image identity changed before recursive inspection"))
      let canonicalPath =
            resolvedExecutableCanonicalPath identity
          context =
            ( canonicalPath,
              machOQueueInheritedRpaths entry
            )
      if context `elem` machOVisitedContexts state
        then walkMachOClosure executableDirectory state remaining
        else do
          unless
            ( length (machOVisitedContexts state)
                < maximumMachOContexts
            )
            (ioError (userError "Poetry Mach-O closure exceeds its context bound"))
          (inspection, stateWithInspection) <-
            cachedMachOInspection state identity
          currentRpaths <-
            requireMachOResolution
              ( expandMachORpathStack
                  canonicalPath
                  executableDirectory
                  (machOQueueInheritedRpaths entry)
                  (machORpaths inspection)
              )
          dependencies <-
            resolveMachODependencies
              canonicalPath
              executableDirectory
              currentRpaths
              (machODependencies inspection)
          dependencyLibraries <-
            mapM
              (uncurry resolveRuntimeLibraryIdentity)
              dependencies
          libraries <-
            foldM
              insertRuntimeLibrary
              (machORuntimeLibraries stateWithInspection)
              dependencyLibraries
          let nextEdges =
                machOEdgesObserved stateWithInspection
                  + fromIntegral
                    (length (machODependencies inspection))
              nextState =
                stateWithInspection
                  { machOVisitedContexts =
                      context
                        : machOVisitedContexts stateWithInspection,
                    machORuntimeLibraries = libraries,
                    machOEdgesObserved = nextEdges
                  }
              nextQueue =
                remaining
                  <> List.sortOn
                    machOQueuePath
                    [ MachOQueueEntry
                        ( Internal.provisioningRuntimeLibraryConfiguredPath
                            library
                        )
                        currentRpaths
                        library
                    | library <- dependencyLibraries
                    ]
          unless
            (nextEdges <= maximumMachOEdges)
            (ioError (userError "Poetry Mach-O closure exceeds its edge bound"))
          validateMachOClosureState nextState
          walkMachOClosure
            executableDirectory
            nextState
            nextQueue

cachedMachOInspection ::
  MachOClosureState ->
  ResolvedExecutableIdentity ->
  IO (MachOInspection, MachOClosureState)
cachedMachOInspection state identity =
  case [ inspection
       | (canonicalPath, _, inspection) <- machOInspections state,
         canonicalPath == resolvedExecutableCanonicalPath identity
       ] of
    inspection : _ -> pure (inspection, state)
    [] -> do
      inspection <- inspectExactMachOImage identity
      let imageBytes =
            fromIntegral
              (Posix.fileSize (resolvedExecutableCanonicalStatus identity))
          nextBytes = machOBytesInspected state + imageBytes
          nextMetadata =
            machOMetadataObserved state
              + machOMetadataBytes inspection
          nextInspections =
            ( resolvedExecutableCanonicalPath identity,
              identity,
              inspection
            )
              : machOInspections state
      unless
        ( length nextInspections <= maximumMachOImages
            && nextBytes <= maximumMachOInspectionBytes
            && nextMetadata <= maximumMachOMetadataBytes
        )
        (ioError (userError "Poetry Mach-O inspection exceeds its image, byte, or metadata bound"))
      pure
        ( inspection,
          state
            { machOInspections = nextInspections,
              machOBytesInspected = nextBytes,
              machOMetadataObserved = nextMetadata
            }
        )

validateMachOClosureState :: MachOClosureState -> IO ()
validateMachOClosureState state = do
  let libraries = machORuntimeLibraries state
      runtimeBytes =
        sum
          ( map
              Internal.provisioningRuntimeLibrarySize
              libraries
          )
  unless
    ( length libraries <= maximumMachORuntimeLibraries
        && runtimeBytes <= maximumMachORuntimeBytes
        && machOEdgesObserved state <= maximumMachOEdges
        && machOBytesInspected state <= maximumMachOInspectionBytes
        && machOMetadataObserved state <= maximumMachOMetadataBytes
    )
    (ioError (userError "Poetry Mach-O closure exceeds its total bound"))

deduplicateRuntimeIdentitySources ::
  [Internal.ProvisioningRuntimeLibraryIdentity] ->
  [Internal.ProvisioningRuntimeLibraryIdentity]
deduplicateRuntimeIdentitySources =
  List.nubBy
    ( \left right ->
        normalise
          (Internal.provisioningRuntimeLibraryCanonicalPath left)
          == normalise
            (Internal.provisioningRuntimeLibraryCanonicalPath right)
    )

resolvedIdentityMatchesRuntimeIdentity ::
  ResolvedExecutableIdentity ->
  Internal.ProvisioningRuntimeLibraryIdentity ->
  Bool
resolvedIdentityMatchesRuntimeIdentity identity expected =
  let status = resolvedExecutableCanonicalStatus identity
   in normalise (resolvedExecutableConfiguredPath identity)
        == normalise
          (Internal.provisioningRuntimeLibraryConfiguredPath expected)
        && normalise (resolvedExecutableCanonicalPath identity)
          == normalise
            (Internal.provisioningRuntimeLibraryCanonicalPath expected)
        && fromIntegral (Posix.deviceID status)
          == Internal.provisioningRuntimeLibraryDeviceId expected
        && fromIntegral (Posix.fileID status)
          == Internal.provisioningRuntimeLibraryFileId expected
        && fromIntegral (Posix.fileMode status)
          == Internal.provisioningRuntimeLibraryMode expected
        && fromIntegral (Posix.fileSize status)
          == Internal.provisioningRuntimeLibrarySize expected
        && resolvedExecutableDigest identity
          == Internal.provisioningRuntimeLibraryDigest expected

insertRuntimeLibrary ::
  [Internal.ProvisioningRuntimeLibraryIdentity] ->
  Internal.ProvisioningRuntimeLibraryIdentity ->
  IO [Internal.ProvisioningRuntimeLibraryIdentity]
insertRuntimeLibrary existing candidate = do
  let sameSource library =
        normalise
          (Internal.provisioningRuntimeLibraryCanonicalPath library)
          == normalise
            (Internal.provisioningRuntimeLibraryCanonicalPath candidate)
      sourceCollisions = filter sameSource existing
  case sourceCollisions of
    [] -> pure (candidate : existing)
    source : _
      | Internal.provisioningRuntimeLibraryLeafName source
          == Internal.provisioningRuntimeLibraryLeafName candidate
          && Internal.provisioningRuntimeLibraryDigest source
            == Internal.provisioningRuntimeLibraryDigest candidate ->
          pure existing
    _ ->
      ioError
        ( userError
            ( "Mach-O runtime library source identity collision: "
                <> Internal.provisioningRuntimeLibraryCanonicalPath candidate
            )
        )

resolveRuntimeLibraryIdentity ::
  FilePath ->
  FilePath ->
  IO Internal.ProvisioningRuntimeLibraryIdentity
resolveRuntimeLibraryIdentity leafName configuredPath = do
  unless
    ( not (null leafName)
        && leafName == takeFileName leafName
        && leafName /= "."
        && leafName /= ".."
    )
    (ioError (userError "Mach-O dependency leaf name is unsafe"))
  identity <- resolveExactExecutableIdentity configuredPath
  pure (runtimeLibraryIdentityFromResolved leafName identity)

runtimeLibraryIdentityFromResolved ::
  FilePath ->
  ResolvedExecutableIdentity ->
  Internal.ProvisioningRuntimeLibraryIdentity
runtimeLibraryIdentityFromResolved leafName identity =
  let status = resolvedExecutableCanonicalStatus identity
   in Internal.ProvisioningRuntimeLibraryIdentity
        { Internal.provisioningRuntimeLibraryLeafName = leafName,
          Internal.provisioningRuntimeLibraryConfiguredPath =
            resolvedExecutableConfiguredPath identity,
          Internal.provisioningRuntimeLibraryCanonicalPath =
            resolvedExecutableCanonicalPath identity,
          Internal.provisioningRuntimeLibraryDeviceId =
            fromIntegral (Posix.deviceID status),
          Internal.provisioningRuntimeLibraryFileId =
            fromIntegral (Posix.fileID status),
          Internal.provisioningRuntimeLibraryMode =
            fromIntegral (Posix.fileMode status),
          Internal.provisioningRuntimeLibrarySize =
            fromIntegral (Posix.fileSize status),
          Internal.provisioningRuntimeLibraryDigest =
            resolvedExecutableDigest identity
        }

resolveExactExecutableIdentity ::
  FilePath ->
  IO ResolvedExecutableIdentity
resolveExactExecutableIdentity path = do
  resolution <- resolveExecutableIdentity path
  case resolution of
    Left failure -> ioError (userError failure)
    Right identity -> pure identity

scanPackageClosureMachOFiles ::
  Internal.ProvisioningPackageClosureIdentity ->
  IO [Internal.ProvisioningRuntimeLibraryIdentity]
scanPackageClosureMachOFiles closure =
  mask $ \restore -> do
    let root = Internal.provisioningPackageClosureRoot closure
    listedRootStatus <- Posix.getSymbolicLinkStatus root
    unless
      (packageClosureRootStatusMatches closure listedRootStatus)
      (ioError (userError "Poetry closure changed before Mach-O scan"))
    rootDescriptor <-
      openFd
        root
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    identities <-
      finallyPreservingPrimary
        ( restore $ do
            openedRootStatus <- Posix.getFdStatus rootDescriptor
            unless
              ( packageClosureRootStatusMatches closure openedRootStatus
                  && stableExecutableStatus
                    listedRootStatus
                    openedRootStatus
              )
              (ioError (userError "Poetry closure changed before descriptor Mach-O scan"))
            (_, observed) <-
              scanMachODirectory
                root
                root
                rootDescriptor
                openedRootStatus
                0
                (0, [])
            finalDescriptorStatus <- Posix.getFdStatus rootDescriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus root
            unless
              ( stableExecutableStatus
                  openedRootStatus
                  finalDescriptorStatus
                  && stableExecutableStatus
                    finalDescriptorStatus
                    finalPathStatus
              )
              (ioError (userError "Poetry closure changed during descriptor Mach-O scan"))
            pure observed
        )
        (closeFd rootDescriptor)
    pure
      ( List.sortOn
          Internal.provisioningRuntimeLibraryCanonicalPath
          identities
      )

packageClosureRootStatusMatches ::
  Internal.ProvisioningPackageClosureIdentity ->
  Posix.FileStatus ->
  Bool
packageClosureRootStatusMatches closure status =
  Posix.isDirectory status
    && not (Posix.isSymbolicLink status)
    && fromIntegral (Posix.deviceID status)
      == Internal.provisioningPackageClosureDeviceId closure
    && fromIntegral (Posix.fileID status)
      == Internal.provisioningPackageClosureFileId closure
    && fromIntegral (Posix.fileMode status)
      == Internal.provisioningPackageClosureMode closure

scanMachODirectory ::
  FilePath ->
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  Int ->
  (Integer, [Internal.ProvisioningRuntimeLibraryIdentity]) ->
  IO (Integer, [Internal.ProvisioningRuntimeLibraryIdentity])
scanMachODirectory root directory descriptor listedStatus depth state = do
  unless
    (depth <= maximumPoetryClosureDepth)
    (ioError (userError "Mach-O scan exceeds package closure depth"))
  unless
    (Posix.isDirectory listedStatus)
    (ioError (userError "Mach-O scan encountered an unsafe directory"))
  entries <-
    listDirectoryBoundedFromDescriptor
      descriptor
      (maximumPoetryClosureFiles - fst state)
  observed <-
    foldM
      (scanMachOEntry root directory descriptor depth)
      state
      entries
  finalStatus <- Posix.getFdStatus descriptor
  unless
    (stableExecutableStatus listedStatus finalStatus)
    (ioError (userError "Mach-O scan directory changed"))
  pure observed

scanMachOEntry ::
  FilePath ->
  FilePath ->
  Fd ->
  Int ->
  (Integer, [Internal.ProvisioningRuntimeLibraryIdentity]) ->
  FilePath ->
  IO (Integer, [Internal.ProvisioningRuntimeLibraryIdentity])
scanMachOEntry root parent parentDescriptor parentDepth state entry = do
  let path = parent </> entry
      nextEntries = fst state + 1
  unless
    (nextEntries <= maximumPoetryClosureFiles)
    (ioError (userError "Mach-O scan exceeds package closure entry bound"))
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
            status <- Posix.getFdStatus childDescriptor
            unless
              (Posix.isDirectory status)
              (ioError (userError ("Mach-O scan child is not a directory: " <> path)))
            observed <-
              scanMachODirectory
                root
                path
                childDescriptor
                status
                (parentDepth + 1)
                (nextEntries, snd state)
            finalStatus <- Posix.getFdStatus childDescriptor
            reopenedStatus <-
              reopenDirectoryEntryStatus parentDescriptor entry
            unless
              ( stableExecutableStatus status finalStatus
                  && stableExecutableStatus finalStatus reopenedStatus
              )
              (ioError (userError ("Mach-O scan directory changed: " <> path)))
            pure observed
        )
        (closeFd childDescriptor)
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
        Right fileDescriptor ->
          finallyPreservingPrimary
            ( do
                status <- Posix.getFdStatus fileDescriptor
                unless
                  (Posix.isRegularFile status)
                  (ioError (userError ("Mach-O scan encountered unsupported entry: " <> path)))
                maybeIdentity <-
                  inspectMachOCandidateDescriptor
                    parentDescriptor
                    entry
                    path
                    fileDescriptor
                    status
                let identities =
                      maybe (snd state) (: snd state) maybeIdentity
                unless
                  (length identities <= maximumMachOImages)
                  (ioError (userError "Poetry package closure has too many Mach-O images"))
                pure (nextEntries, identities)
            )
            (closeFd fileDescriptor)
        Left _ -> do
          validateSkippedClosureSymlink parentDescriptor parent path
          pure (nextEntries, snd state)

inspectMachOCandidateDescriptor ::
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  IO (Maybe Internal.ProvisioningRuntimeLibraryIdentity)
inspectMachOCandidateDescriptor
  parentDescriptor
  entry
  path
  descriptor
  openedStatus = do
    magic <- PosixByteString.fdRead descriptor 4
    maybeIdentity <-
      if supportedMachOMagic magic
        then do
          let expectedBytes =
                fromIntegral (Posix.fileSize openedStatus)
          unless
            (expectedBytes <= maximumExactRuntimeFileBytes)
            (ioError (userError "Mach-O candidate exceeds its per-image bound"))
          _ <- fdSeek descriptor AbsoluteSeek 0
          digest <-
            digestExactProvisioningDescriptor descriptor expectedBytes
          let identity =
                ResolvedExecutableIdentity
                  { resolvedExecutableConfiguredPath = path,
                    resolvedExecutableCanonicalPath = path,
                    resolvedExecutableConfiguredStatus = openedStatus,
                    resolvedExecutableCanonicalStatus = openedStatus,
                    resolvedExecutableDigest = digest
                  }
          pure
            ( Just
                ( runtimeLibraryIdentityFromResolved
                    (takeFileName path)
                    identity
                )
            )
        else pure Nothing
    finalStatus <- Posix.getFdStatus descriptor
    reopenedStatus <- reopenFileEntryStatus parentDescriptor entry
    unless
      ( stableExecutableStatus openedStatus finalStatus
          && stableExecutableStatus finalStatus reopenedStatus
      )
      (ioError (userError "Mach-O candidate changed during descriptor scan"))
    pure maybeIdentity

validateSkippedClosureSymlink ::
  Fd ->
  FilePath ->
  FilePath ->
  IO ()
validateSkippedClosureSymlink parentDescriptor parentPath path = do
  parentStatus <- Posix.getFdStatus parentDescriptor
  parentPathStatus <- Posix.getSymbolicLinkStatus parentPath
  unless
    (stableExecutableStatus parentStatus parentPathStatus)
    (ioError (userError ("Mach-O symlink parent changed: " <> parentPath)))
  status <- Posix.getSymbolicLinkStatus path
  unless
    (Posix.isSymbolicLink status)
    (ioError (userError ("Mach-O scan entry is neither openable nor a symlink: " <> path)))
  target <- Posix.readSymbolicLink path
  finalStatus <- Posix.getSymbolicLinkStatus path
  finalTarget <- Posix.readSymbolicLink path
  finalParentStatus <- Posix.getFdStatus parentDescriptor
  finalParentPathStatus <- Posix.getSymbolicLinkStatus parentPath
  unless
    ( stableExecutableStatus status finalStatus
        && target == finalTarget
        && stableExecutableStatus parentStatus finalParentStatus
        && stableExecutableStatus finalParentStatus finalParentPathStatus
    )
    (ioError (userError ("Mach-O scan symlink changed: " <> path)))

supportedMachOMagic :: ByteString.ByteString -> Bool
supportedMachOMagic bytes =
  bytes
    `elem` [ ByteString.pack [0xcf, 0xfa, 0xed, 0xfe],
             ByteString.pack [0xca, 0xfe, 0xba, 0xbe],
             ByteString.pack [0xca, 0xfe, 0xba, 0xbf]
           ]

inspectExactMachOImage ::
  ResolvedExecutableIdentity ->
  IO MachOInspection
inspectExactMachOImage identity = do
  contents <- readExactExecutableBytes identity
  requireMachOResolution (parseMachOInspection contents)

readExactExecutableBytes ::
  ResolvedExecutableIdentity ->
  IO ByteString.ByteString
readExactExecutableBytes identity =
  mask $ \restore -> do
    let path = resolvedExecutableCanonicalPath identity
        expectedStatus =
          resolvedExecutableCanonicalStatus identity
        expectedSize =
          fromIntegral (Posix.fileSize expectedStatus)
    unless
      ( expectedSize >= 0
          && expectedSize <= maximumExactRuntimeFileBytes
          && expectedSize <= fromIntegral (maxBound :: Int)
      )
      (ioError (userError "Mach-O image exceeds its fixed per-file bound"))
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
          openedStatus <- Posix.getFdStatus descriptor
          unless
            (stableExecutableStatus expectedStatus openedStatus)
            (ioError (userError "Mach-O image changed before exact read"))
          contents <-
            readProvisioningDescriptorBounded
              descriptor
              (fromIntegral expectedSize)
              0
              []
          finalStatus <- Posix.getFdStatus descriptor
          finalPathStatus <- Posix.getSymbolicLinkStatus path
          unless
            ( ByteString.length contents == fromIntegral expectedSize
                && stableExecutableStatus openedStatus finalStatus
                && stableExecutableStatus finalStatus finalPathStatus
            )
            (ioError (userError "Mach-O image changed during exact read"))
          pure contents
      )
      (closeFd descriptor)

parseMachOInspection ::
  ByteString.ByteString ->
  Either String MachOInspection
parseMachOInspection contents
  | ByteString.take 4 contents
      == ByteString.pack [0xcf, 0xfa, 0xed, 0xfe] =
      parseThinMachO contents
  | ByteString.take 4 contents
      == ByteString.pack [0xca, 0xfe, 0xba, 0xbe] =
      selectFatMachOSlice False contents >>= parseThinMachO
  | ByteString.take 4 contents
      == ByteString.pack [0xca, 0xfe, 0xba, 0xbf] =
      selectFatMachOSlice True contents >>= parseThinMachO
  | otherwise = Left "unsupported or non-arm64 Mach-O magic"

inspectMachOFixtureForTest ::
  ByteString.ByteString ->
  Either String ([FilePath], [FilePath])
inspectMachOFixtureForTest contents = do
  inspection <- parseMachOInspection contents
  pure (machODependencies inspection, machORpaths inspection)

data MachOFixtureWalk = MachOFixtureWalk
  { fixtureVisitedContexts :: ![(FilePath, [FilePath])],
    fixtureVisitedImages :: ![FilePath],
    fixtureEdges :: !Integer,
    fixtureBytes :: !Integer,
    fixturePluginRoots :: ![FilePath]
  }

resolveMachOPathsFixtureForTest ::
  FilePath ->
  FilePath ->
  [(FilePath, ByteString.ByteString)] ->
  Either String MachOFixturePlan
resolveMachOPathsFixtureForTest
  candidateRoot
  executablePath
  images = do
    unlessEither
      ( validNormalizedAbsolutePath candidateRoot
          && validNormalizedAbsolutePath executablePath
          && all (validNormalizedAbsolutePath . fst) images
          && length images
            == length (List.nub (map (normalise . fst) images))
          && all
            ( (<= maximumExactRuntimeFileBytes)
                . fromIntegral
                . ByteString.length
                . snd
            )
            images
      )
      "Mach-O fixture graph has an invalid root, image path, duplicate, or file bound"
    _ <-
      maybe
        (Left "Mach-O fixture graph omits its exact executable")
        Right
        (lookup executablePath images)
    finalState <-
      walkFixtureGraph
        images
        (takeDirectory executablePath)
        MachOFixtureWalk
          { fixtureVisitedContexts = [],
            fixtureVisitedImages = [],
            fixtureEdges = 0,
            fixtureBytes = 0,
            fixturePluginRoots = []
          }
        [(executablePath, [])]
    let copiedSources =
          List.sort
            (filter (/= executablePath) (fixtureVisitedImages finalState))
        plannedCopies =
          map
            ( \source ->
                ( source,
                  fixtureOwnedPath
                    candidateRoot
                    (fixturePluginRoots finalState)
                    source
                )
            )
            copiedSources
        destinations = map snd plannedCopies
        copiedBytes =
          sum
            [ fromIntegral (ByteString.length contents)
            | source <- copiedSources,
              Just contents <- [lookup source images]
            ]
    unlessEither
      ( length plannedCopies <= maximumMachORuntimeLibraries
          && copiedBytes <= maximumMachORuntimeBytes
          && length destinations
            == length (List.nub (map normalise destinations))
      )
      "Mach-O fixture graph has a destination collision or exceeds its copy bound"
    pure
      MachOFixturePlan
        { machOFixturePlannedCopies = plannedCopies,
          machOFixtureImageCount =
            length (fixtureVisitedImages finalState),
          machOFixtureByteCount = fixtureBytes finalState,
          machOFixtureContextCount =
            length (fixtureVisitedContexts finalState),
          machOFixtureEdgeCount = fixtureEdges finalState,
          machOFixturePluginRootCount =
            length (fixturePluginRoots finalState)
        }

walkFixtureGraph ::
  [(FilePath, ByteString.ByteString)] ->
  FilePath ->
  MachOFixtureWalk ->
  [(FilePath, [FilePath])] ->
  Either String MachOFixtureWalk
walkFixtureGraph images executableDirectory state queue =
  case queue of
    [] -> Right state
    (imagePath, inheritedRpaths) : remaining ->
      let context = (imagePath, inheritedRpaths)
       in if context `elem` fixtureVisitedContexts state
            then
              walkFixtureGraph
                images
                executableDirectory
                state
                remaining
            else do
              contents <-
                maybe
                  (Left ("Mach-O fixture dependency is unresolved: " <> imagePath))
                  Right
                  (lookup imagePath images)
              inspection <- parseMachOInspection contents
              localRpaths <-
                expandMachORpathStack
                  imagePath
                  executableDirectory
                  inheritedRpaths
                  (machORpaths inspection)
              dependencies <-
                fmap
                  concat
                  ( mapM
                      ( resolveMachOFixtureDependency
                          images
                          imagePath
                          executableDirectory
                          localRpaths
                      )
                      (machODependencies inspection)
                  )
              let discoveredPluginRoots =
                    List.nub
                      ( List.sort
                          ( fixturePluginRoots state
                              <> foldr
                                addFixturePluginRoot
                                []
                                (imagePath : dependencies)
                          )
                      )
                  pluginImages =
                    [ path
                    | root <- discoveredPluginRoots,
                      (path, _) <- images,
                      writerPathWithin root path
                    ]
                  newlyVisitedImage =
                    imagePath `notElem` fixtureVisitedImages state
                  nextImages =
                    if newlyVisitedImage
                      then imagePath : fixtureVisitedImages state
                      else fixtureVisitedImages state
                  nextBytes =
                    fixtureBytes state
                      + if newlyVisitedImage
                        then fromIntegral (ByteString.length contents)
                        else 0
                  nextEdges =
                    fixtureEdges state
                      + fromIntegral
                        (length (machODependencies inspection))
                  nextContexts =
                    context : fixtureVisitedContexts state
                  nextState =
                    state
                      { fixtureVisitedContexts = nextContexts,
                        fixtureVisitedImages = nextImages,
                        fixtureEdges = nextEdges,
                        fixtureBytes = nextBytes,
                        fixturePluginRoots = discoveredPluginRoots
                      }
              unlessEither
                ( length nextImages <= maximumMachOImages
                    && length nextContexts <= maximumMachOContexts
                    && nextEdges <= maximumMachOEdges
                    && nextBytes <= maximumMachOInspectionBytes
                    && length discoveredPluginRoots <= 1
                    && length pluginImages <= maximumMachORuntimeLibraries
                )
                "Mach-O fixture graph exceeds its image, context, edge, byte, or plugin bound"
              walkFixtureGraph
                images
                executableDirectory
                nextState
                ( remaining
                    <> map (,localRpaths) (List.sort dependencies)
                    <> map (,localRpaths) (List.sort pluginImages)
                )
  where
    addFixturePluginRoot path roots =
      case homebrewGgmlLibexecRoot path of
        Nothing -> roots
        Just root
          | any (writerPathWithin root . fst) images ->
              root : roots
          | otherwise -> roots

resolveMachOFixtureDependency ::
  [(FilePath, ByteString.ByteString)] ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  FilePath ->
  Either String [FilePath]
resolveMachOFixtureDependency
  images
  loaderPath
  executableDirectory
  rpaths
  dependency
    | isAbsolute dependency =
        requireFixtureImage dependency
    | dependency == "@loader_path" =
        requireFixtureImage (takeDirectory loaderPath)
    | Just suffix <- List.stripPrefix "@loader_path/" dependency = do
        safeSuffix <- requireSafeMachOFixtureSuffix suffix
        requireFixtureImage
          (normalise (takeDirectory loaderPath </> safeSuffix))
    | dependency == "@executable_path" =
        requireFixtureImage executableDirectory
    | Just suffix <- List.stripPrefix "@executable_path/" dependency = do
        safeSuffix <- requireSafeMachOFixtureSuffix suffix
        requireFixtureImage
          (normalise (executableDirectory </> safeSuffix))
    | Just suffix <- List.stripPrefix "@rpath/" dependency = do
        safeSuffix <- requireSafeMachOFixtureSuffix suffix
        requireFirstFixtureImage
          [normalise (rpath </> safeSuffix) | rpath <- rpaths]
    | otherwise =
        Left
          ( "unsupported Mach-O fixture dependency install name: "
              <> dependency
          )
    where
      requireFixtureImage path
        | not (validNormalizedAbsolutePath path) =
            Left ("Mach-O fixture dependency resolved unsafely: " <> path)
        | systemMachOPath path = Right []
        | path `elem` map fst images = Right [path]
        | otherwise =
            Left ("Mach-O fixture dependency is unresolved: " <> path)

      requireFirstFixtureImage candidates =
        case candidates of
          [] ->
            Left ("Mach-O fixture @rpath dependency is unresolved: " <> dependency)
          candidate : remaining
            | candidate `elem` map fst images ->
                Right [candidate]
            | otherwise -> requireFirstFixtureImage remaining

requireSafeMachOFixtureSuffix :: FilePath -> Either String FilePath
requireSafeMachOFixtureSuffix suffix =
  let components = splitDirectories suffix
   in if not (null suffix)
        && not (isAbsolute suffix)
        && '\NUL' `notElem` suffix
        && all
          (\component -> component /= "." && component /= ".." && component /= "/")
          components
        then Right suffix
        else Left "Mach-O fixture dependency suffix traverses its anchor"

validNormalizedAbsolutePath :: FilePath -> Bool
validNormalizedAbsolutePath path =
  isAbsolute path
    && normalise path == path
    && '\NUL' `notElem` path

fixtureOwnedPath ::
  FilePath ->
  [FilePath] ->
  FilePath ->
  FilePath
fixtureOwnedPath candidateRoot pluginRoots source =
  case [ makeRelative pluginRoot source
       | pluginRoot <- pluginRoots,
         writerPathWithin pluginRoot source
       ] of
    relativePluginPath : _ ->
      candidateRoot </> "native" </> "libexec" </> relativePluginPath
    [] ->
      case frameworkRelativeSuffix source of
        Just relativeFrameworkPath ->
          candidateRoot
            </> "native"
            </> "frameworks"
            </> relativeFrameworkPath
        Nothing ->
          candidateRoot </> "native" </> "lib" </> takeFileName source

selectFatMachOSlice ::
  Bool ->
  ByteString.ByteString ->
  Either String ByteString.ByteString
selectFatMachOSlice is64 contents = do
  architectureCount <- readWord32BE contents 4
  unlessEither
    (architectureCount > 0 && architectureCount <= 32)
    "fat Mach-O architecture count is invalid"
  let recordBytes = if is64 then 32 else 20
      offsets =
        [ 8 + index * recordBytes
        | index <- [0 .. fromIntegral architectureCount - 1]
        ]
  candidates <-
    mapM
      ( \offset -> do
          cpuType <- readWord32BE contents offset
          if cpuType /= 0x0100000c
            then pure Nothing
            else do
              sliceOffset <-
                if is64
                  then readWord64BE contents (offset + 8)
                  else fromIntegral <$> readWord32BE contents (offset + 8)
              sliceSize <-
                if is64
                  then readWord64BE contents (offset + 16)
                  else fromIntegral <$> readWord32BE contents (offset + 12)
              pure (Just (sliceOffset, sliceSize))
      )
      offsets
  case catMaybes candidates of
    [(sliceOffset, sliceSize)] ->
      boundedByteStringSlice contents sliceOffset sliceSize
    [] -> Left "fat Mach-O has no arm64 slice"
    _ -> Left "fat Mach-O has ambiguous arm64 slices"

parseThinMachO ::
  ByteString.ByteString ->
  Either String MachOInspection
parseThinMachO contents = do
  unlessEither
    (ByteString.take 4 contents == ByteString.pack [0xcf, 0xfa, 0xed, 0xfe])
    "Mach-O slice is not little-endian 64-bit"
  cpuType <- readWord32LE contents 4
  unlessEither
    (cpuType == 0x0100000c)
    "Mach-O slice is not arm64"
  commandCount <- readWord32LE contents 16
  commandBytes <- readWord32LE contents 20
  unlessEither
    ( commandCount <= maximumMachOLoadCommands
        && commandBytes <= maximumMachOLoadCommandBytes
        && 32 + fromIntegral commandBytes
          <= ByteString.length contents
    )
    "Mach-O load-command table exceeds its fixed bound"
  walkCommands
    contents
    commandCount
    32
    (32 + fromIntegral commandBytes)
    []
    []
    0

walkCommands ::
  ByteString.ByteString ->
  Word32 ->
  Int ->
  Int ->
  [FilePath] ->
  [FilePath] ->
  Integer ->
  Either String MachOInspection
walkCommands contents commandsRemaining offset commandEnd dependencies rpaths metadataBytes
  | commandsRemaining == 0 = do
      unlessEither
        ( length dependencies <= 256
            && length rpaths <= maximumMachORpathsPerImage
            && metadataBytes <= maximumMachOMetadataBytes
        )
        "Mach-O dependency metadata exceeds its fixed bound"
      pure
        MachOInspection
          { machODependencies = List.nub (reverse dependencies),
            machORpaths = List.nub (reverse rpaths),
            machOMetadataBytes = metadataBytes
          }
  | otherwise = do
      command <- readWord32LE contents offset
      commandSize <- readWord32LE contents (offset + 4)
      let commandSizeInt = fromIntegral commandSize
          nextOffset = offset + commandSizeInt
      unlessEither
        ( commandSizeInt >= 8
            && nextOffset <= commandEnd
        )
        "Mach-O load command size is invalid"
      if command `elem` machODylibLoadCommands
        then do
          value <- readMachOCommandString contents offset commandSizeInt
          walkCommands
            contents
            (commandsRemaining - 1)
            nextOffset
            commandEnd
            (value : dependencies)
            rpaths
            (metadataBytes + fromIntegral (length value))
        else
          if command == 0x8000001c
            then do
              value <- readMachOCommandString contents offset commandSizeInt
              walkCommands
                contents
                (commandsRemaining - 1)
                nextOffset
                commandEnd
                dependencies
                (value : rpaths)
                (metadataBytes + fromIntegral (length value))
            else
              walkCommands
                contents
                (commandsRemaining - 1)
                nextOffset
                commandEnd
                dependencies
                rpaths
                metadataBytes

machODylibLoadCommands :: [Word32]
machODylibLoadCommands =
  [ 0x0000000c,
    0x80000018,
    0x00000020,
    0x8000001f,
    0x80000023
  ]

readMachOCommandString ::
  ByteString.ByteString ->
  Int ->
  Int ->
  Either String FilePath
readMachOCommandString contents commandOffset commandSize = do
  stringOffset <- fromIntegral <$> readWord32LE contents (commandOffset + 8)
  unlessEither
    ( stringOffset >= 12
        && stringOffset < commandSize
    )
    "Mach-O command string offset is invalid"
  let available =
        ByteString.take
          (commandSize - stringOffset)
          (ByteString.drop (commandOffset + stringOffset) contents)
      encoded = ByteString.takeWhile (/= 0) available
  unlessEither
    ( not (ByteString.null encoded)
        && ByteString.length encoded <= 4096
        && ByteString.length encoded < ByteString.length available
    )
    "Mach-O command string is empty, unterminated, or oversized"
  textValue <-
    either
      (const (Left "Mach-O command string is not UTF-8"))
      Right
      (TextEncoding.decodeUtf8' encoded)
  let value = Text.unpack textValue
  unlessEither
    ('\NUL' `notElem` value)
    "Mach-O command string contains NUL"
  pure value

readWord32LE ::
  ByteString.ByteString ->
  Int ->
  Either String Word32
readWord32LE bytes offset = do
  octets <- readOctets bytes offset 4
  pure
    ( foldr
        (.|.)
        0
        [ fromIntegral octet `shiftL` shift
        | (octet, shift) <- zip octets [0, 8, 16, 24]
        ]
    )

readWord32BE ::
  ByteString.ByteString ->
  Int ->
  Either String Word32
readWord32BE bytes offset = do
  octets <- readOctets bytes offset 4
  pure
    ( foldr
        (.|.)
        0
        [ fromIntegral octet `shiftL` shift
        | (octet, shift) <- zip octets [24, 16, 8, 0]
        ]
    )

readWord64BE ::
  ByteString.ByteString ->
  Int ->
  Either String Word64
readWord64BE bytes offset = do
  octets <- readOctets bytes offset 8
  pure
    ( foldr
        (.|.)
        0
        [ fromIntegral octet `shiftL` shift
        | (octet, shift) <-
            zip octets [56, 48, 40, 32, 24, 16, 8, 0]
        ]
    )

readOctets ::
  ByteString.ByteString ->
  Int ->
  Int ->
  Either String [Word8]
readOctets bytes offset count
  | offset < 0
      || count < 0
      || offset + count > ByteString.length bytes =
      Left "Mach-O structure is truncated"
  | otherwise =
      Right
        [ ByteString.index bytes index
        | index <- [offset .. offset + count - 1]
        ]

boundedByteStringSlice ::
  ByteString.ByteString ->
  Word64 ->
  Word64 ->
  Either String ByteString.ByteString
boundedByteStringSlice contents sliceOffset sliceSize = do
  let contentsLength = fromIntegral (ByteString.length contents) :: Word64
  unlessEither
    ( sliceSize > 0
        && sliceOffset <= contentsLength
        && sliceSize <= contentsLength - sliceOffset
        && sliceOffset <= fromIntegral (maxBound :: Int)
        && sliceSize <= fromIntegral (maxBound :: Int)
    )
    "fat Mach-O slice is out of bounds"
  pure
    ( ByteString.take
        (fromIntegral sliceSize)
        (ByteString.drop (fromIntegral sliceOffset) contents)
    )

unlessEither :: Bool -> String -> Either String ()
unlessEither predicate failure
  | predicate = Right ()
  | otherwise = Left failure

requireMachOResolution :: Either String value -> IO value
requireMachOResolution =
  either (ioError . userError) pure

expandMachORpathStack ::
  FilePath ->
  FilePath ->
  [FilePath] ->
  [FilePath] ->
  Either String [FilePath]
expandMachORpathStack loaderPath executableDirectory inherited rawRpaths = do
  current <-
    mapM
      (expandMachORpath loaderPath executableDirectory)
      rawRpaths
  let stack = List.nub (current <> inherited)
  unlessEither
    ( length rawRpaths <= maximumMachORpathsPerImage
        && length stack <= maximumMachORpathStack
        && all isAbsolute stack
    )
    "Mach-O inherited rpath stack exceeds its fixed bound"
  pure stack

expandMachORpath ::
  FilePath ->
  FilePath ->
  FilePath ->
  Either String FilePath
expandMachORpath loaderPath executableDirectory rawPath
  | rawPath == "@loader_path" =
      pure (takeDirectory loaderPath)
  | Just suffix <- List.stripPrefix "@loader_path/" rawPath =
      pure (normalise (takeDirectory loaderPath </> suffix))
  | rawPath == "@executable_path" =
      pure executableDirectory
  | Just suffix <- List.stripPrefix "@executable_path/" rawPath =
      pure (normalise (executableDirectory </> suffix))
  | isAbsolute rawPath = pure (normalise rawPath)
  | otherwise =
      Left ("unsupported Mach-O LC_RPATH: " <> rawPath)

resolveMachODependencies ::
  FilePath ->
  FilePath ->
  [FilePath] ->
  [FilePath] ->
  IO [(FilePath, FilePath)]
resolveMachODependencies loaderPath executableDirectory rpaths dependencies =
  fmap
    concat
    ( mapM
        (resolveMachODependency loaderPath executableDirectory rpaths)
        dependencies
    )

resolveMachODependency ::
  FilePath ->
  FilePath ->
  [FilePath] ->
  FilePath ->
  IO [(FilePath, FilePath)]
resolveMachODependency loaderPath executableDirectory rpaths dependency =
  do
    configuredPath <-
      if
        | isAbsolute dependency ->
            pure dependency
        | dependency == "@loader_path" ->
            pure (takeDirectory loaderPath)
        | Just suffix <- List.stripPrefix "@loader_path/" dependency ->
            anchoredMachOPath (takeDirectory loaderPath) suffix dependency
        | dependency == "@executable_path" ->
            pure executableDirectory
        | Just suffix <- List.stripPrefix "@executable_path/" dependency ->
            anchoredMachOPath executableDirectory suffix dependency
        | Just suffix <- List.stripPrefix "@rpath/" dependency -> do
            safeSuffix <- requireSafeMachORelativeSuffix suffix dependency
            firstExistingMachOPath
              [ rpath </> safeSuffix
              | rpath <- rpaths
              ]
              dependency
        | otherwise ->
            ioError
              (userError ("unsupported Mach-O dependency install name: " <> dependency))
    canonicalPath <- Directory.canonicalizePath configuredPath
    unless
      (isAbsolute canonicalPath)
      (ioError (userError ("Mach-O dependency did not resolve absolutely: " <> dependency)))
    if systemMachOPath canonicalPath
      then pure []
      else
        pure
          [ (takeFileName dependency, canonicalPath)
          ]

anchoredMachOPath ::
  FilePath ->
  FilePath ->
  FilePath ->
  IO FilePath
anchoredMachOPath anchor suffix installName = do
  safeSuffix <- requireSafeMachORelativeSuffix suffix installName
  pure (anchor </> safeSuffix)

requireSafeMachORelativeSuffix ::
  FilePath ->
  FilePath ->
  IO FilePath
requireSafeMachORelativeSuffix suffix installName = do
  let components = splitDirectories suffix
  unless
    ( not (null suffix)
        && not (isAbsolute suffix)
        && '\NUL' `notElem` suffix
        && all
          (\component -> component /= ".." && component /= "." && component /= "/")
          components
    )
    (ioError (userError ("Mach-O install name has an unsafe relative suffix: " <> installName)))
  pure suffix

firstExistingMachOPath ::
  [FilePath] ->
  FilePath ->
  IO FilePath
firstExistingMachOPath candidates dependency =
  case candidates of
    [] ->
      ioError
        (userError ("no inherited LC_RPATH resolves dependency " <> dependency))
    candidate : remaining -> do
      status <- try @IOException (Posix.getSymbolicLinkStatus candidate)
      case status of
        Right observed
          | Posix.isRegularFile observed
              || Posix.isSymbolicLink observed ->
              pure candidate
        _ -> firstExistingMachOPath remaining dependency

systemMachOPath :: FilePath -> Bool
systemMachOPath path =
  isAbsolute path
    && any
      (`List.isPrefixOf` (path <> "/"))
      [ "/System/Library/",
        "/usr/lib/",
        "/Library/Apple/System/Library/"
      ]

resolvePoetrySitePackagesRoot :: FilePath -> IO FilePath
resolvePoetrySitePackagesRoot interpreterPath =
  mask $ \restore -> do
    let libraryRoot =
          takeDirectory (takeDirectory interpreterPath)
            </> "lib"
    listedStatus <- Posix.getSymbolicLinkStatus libraryRoot
    descriptor <-
      openFd
        libraryRoot
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    candidates <-
      finallyPreservingPrimary
        ( restore $ do
            openedStatus <- Posix.getFdStatus descriptor
            unless
              ( Posix.isDirectory openedStatus
                  && stableExecutableStatus listedStatus openedStatus
              )
              (ioError (userError "Poetry library root changed before bounded enumeration"))
            entries <-
              listDirectoryBoundedFromDescriptor
                descriptor
                maximumPoetryLibraryEntries
            observed <-
              foldM
                (retainSitePackagesDirectory libraryRoot descriptor)
                []
                [entry | entry <- entries, "python" `List.isPrefixOf` entry]
            finalDescriptorStatus <- Posix.getFdStatus descriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus libraryRoot
            unless
              ( stableExecutableStatus openedStatus finalDescriptorStatus
                  && stableExecutableStatus
                    finalDescriptorStatus
                    finalPathStatus
              )
              (ioError (userError "Poetry library root changed during bounded enumeration"))
            pure observed
        )
        (closeFd descriptor)
    case List.sort candidates of
      [path] -> pure path
      _ ->
        ioError
          ( userError
              ( "Poetry interpreter must have exactly one site-packages closure under "
                  <> libraryRoot
              )
          )
  where
    retainSitePackagesDirectory libraryRoot libraryDescriptor paths entry = do
      pythonResult <-
        try @IOException
          ( openFdAt
              (Just libraryDescriptor)
              entry
              ReadOnly
              defaultFileFlags
                { nofollow = True,
                  directory = True,
                  cloexec = True
                }
          )
      case pythonResult of
        Left _ -> pure paths
        Right pythonDescriptor ->
          finallyPreservingPrimary
            ( do
                siteResult <-
                  try @IOException
                    ( openFdAt
                        (Just pythonDescriptor)
                        "site-packages"
                        ReadOnly
                        defaultFileFlags
                          { nofollow = True,
                            directory = True,
                            cloexec = True
                          }
                    )
                case siteResult of
                  Left _ -> pure paths
                  Right siteDescriptor ->
                    finallyPreservingPrimary
                      ( do
                          siteStatus <- Posix.getFdStatus siteDescriptor
                          unless
                            (Posix.isDirectory siteStatus)
                            (ioError (userError "Poetry site-packages entry is not a directory"))
                          reopenedStatus <-
                            reopenDirectoryEntryStatus pythonDescriptor "site-packages"
                          unless
                            (stableExecutableStatus siteStatus reopenedStatus)
                            (ioError (userError "Poetry site-packages entry changed during resolution"))
                          pure
                            ( (libraryRoot </> entry </> "site-packages")
                                : paths
                            )
                      )
                      (closeFd siteDescriptor)
            )
            (closeFd pythonDescriptor)

maximumPoetryLibraryEntries :: Integer
maximumPoetryLibraryEntries = 256

maximumPoetrySitePackageEntries :: Integer
maximumPoetrySitePackageEntries = 10000

maximumPoetryPthFiles :: Int
maximumPoetryPthFiles = 64

maximumPoetryPthRoots :: Int
maximumPoetryPthRoots = 128

maximumPoetryPthLines :: Int
maximumPoetryPthLines = 1024

maximumPoetryPthBytes :: Integer
maximumPoetryPthBytes = 1024 * 1024

readPoetryPthRoots :: FilePath -> IO [FilePath]
readPoetryPthRoots sitePackagesRoot =
  mask $ \restore -> do
    listedStatus <- Posix.getSymbolicLinkStatus sitePackagesRoot
    descriptor <-
      openFd
        sitePackagesRoot
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    roots <-
      finallyPreservingPrimary
        ( restore $ do
            openedStatus <- Posix.getFdStatus descriptor
            unless
              ( Posix.isDirectory openedStatus
                  && stableExecutableStatus listedStatus openedStatus
              )
              (ioError (userError "Poetry site-packages root changed before .pth enumeration"))
            entries <-
              listDirectoryBoundedFromDescriptor
                descriptor
                maximumPoetrySitePackageEntries
            let pthEntries =
                  [entry | entry <- entries, ".pth" `List.isSuffixOf` entry]
            unless
              (length pthEntries <= maximumPoetryPthFiles)
              (ioError (userError "Poetry closure has too many .pth files"))
            (_, _, observedRoots) <-
              foldM
                (readPthFile descriptor)
                (0, 0, [])
                pthEntries
            finalDescriptorStatus <- Posix.getFdStatus descriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus sitePackagesRoot
            unless
              ( stableExecutableStatus openedStatus finalDescriptorStatus
                  && stableExecutableStatus
                    finalDescriptorStatus
                    finalPathStatus
              )
              (ioError (userError "Poetry site-packages root changed during .pth enumeration"))
            pure observedRoots
        )
        (closeFd descriptor)
    canonicalRoots <- mapM Directory.canonicalizePath roots
    let uniqueRoots = List.nub (List.sort canonicalRoots)
    unless
      (length uniqueRoots <= maximumPoetryPthRoots)
      (ioError (userError "Poetry .pth closure has too many distinct roots"))
    pure uniqueRoots
  where
    readPthFile parentDescriptor (bytesSeen, linesSeen, roots) entry = do
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
        ( do
            openedStatus <- Posix.getFdStatus descriptor
            unless
              (Posix.isRegularFile openedStatus)
              (ioError (userError "Poetry .pth entry is not a regular file"))
            let fileBytes = fromIntegral (Posix.fileSize openedStatus)
                nextBytes = bytesSeen + fileBytes
            unless
              ( fileBytes <= 64 * 1024
                  && nextBytes <= maximumPoetryPthBytes
              )
              (ioError (userError "Poetry .pth metadata exceeds its aggregate byte bound"))
            contents <-
              readExactProvisioningDescriptorBytes descriptor fileBytes
            finalStatus <- Posix.getFdStatus descriptor
            reopenedStatus <- reopenFileEntryStatus parentDescriptor entry
            unless
              ( stableExecutableStatus openedStatus finalStatus
                  && stableExecutableStatus finalStatus reopenedStatus
              )
              (ioError (userError "Poetry .pth file changed during exact read"))
            text <-
              either
                (ioError . userError . ("Poetry .pth file is not UTF-8: " <>) . show)
                pure
                (TextEncoding.decodeUtf8' contents)
            let meaningfulLines =
                  [ stripped
                  | line <- Text.lines text,
                    let stripped = Text.strip line,
                    not (Text.null stripped),
                    not ("#" `Text.isPrefixOf` stripped)
                  ]
                nextLines = linesSeen + length meaningfulLines
            unless
              ( nextLines <= maximumPoetryPthLines
                  && length roots + length meaningfulLines
                    <= maximumPoetryPthRoots
              )
              (ioError (userError "Poetry .pth metadata exceeds its aggregate line/root bound"))
            parsed <- mapM parsePthLine meaningfulLines
            pure (nextBytes, nextLines, roots <> parsed)
        )
        (closeFd descriptor)

    parsePthLine line = do
      pathText <-
        maybe
          (ioError (userError "Poetry .pth closure contains executable or unsupported syntax"))
          pure
          ( Text.stripSuffix "')"
              =<< Text.stripPrefix "import site; site.addsitedir('" line
          )
      let path = Text.unpack pathText
      unless
        (isAbsolute path && '\NUL' `notElem` path)
        (ioError (userError "Poetry .pth closure root is not an absolute path"))
      pure path

resolvePackageClosureIdentity ::
  Internal.ProvisioningPackageClosureRole ->
  FilePath ->
  IO Internal.ProvisioningPackageClosureIdentity
resolvePackageClosureIdentity role closureRoot =
  mask $ \restore -> do
    listedRootStatus <- Posix.getSymbolicLinkStatus closureRoot
    unless
      ( Posix.isDirectory listedRootStatus
          && not (Posix.isSymbolicLink listedRootStatus)
      )
      (ioError (userError "Poetry package closure root is not a real directory"))
    rootDescriptor <-
      openFd
        closureRoot
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    (observed, stableRootStatus) <-
      finallyPreservingPrimary
        ( restore $ do
            openedRootStatus <- Posix.getFdStatus rootDescriptor
            unless
              ( stableExecutableStatus listedRootStatus openedRootStatus
                  && Posix.isDirectory openedRootStatus
              )
              (ioError (userError "Poetry package closure root changed before descriptor traversal"))
            result <-
              digestPackageClosure
                (role == Internal.ProvisioningPythonHomeClosure)
                closureRoot
                closureRoot
                rootDescriptor
                openedRootStatus
                "."
                0
                (0, 0, SHA256.update SHA256.init "infernix-poetry-closure-v2\NUL")
            finalDescriptorStatus <- Posix.getFdStatus rootDescriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus closureRoot
            unless
              ( stableExecutableStatus openedRootStatus finalDescriptorStatus
                  && stableExecutableStatus
                    finalDescriptorStatus
                    finalPathStatus
              )
              (ioError (userError "Poetry package closure root changed during descriptor traversal"))
            pure (result, finalDescriptorStatus)
        )
        (closeFd rootDescriptor)
    pure
      Internal.ProvisioningPackageClosureIdentity
        { Internal.provisioningPackageClosureRole = role,
          Internal.provisioningPackageClosureRoot = closureRoot,
          Internal.provisioningPackageClosureDeviceId =
            fromIntegral (Posix.deviceID stableRootStatus),
          Internal.provisioningPackageClosureFileId =
            fromIntegral (Posix.fileID stableRootStatus),
          Internal.provisioningPackageClosureMode =
            fromIntegral (Posix.fileMode stableRootStatus),
          Internal.provisioningPackageClosureBytes = closureBytes observed,
          Internal.provisioningPackageClosureFiles = closureFiles observed,
          Internal.provisioningPackageClosureDigest =
            "sha256:"
              <> TextEncoding.decodeUtf8
                (Base16.encode (SHA256.finalize (closureDigestContext observed)))
        }

maximumPoetryClosureBytes :: Integer
maximumPoetryClosureBytes = 512 * 1024 * 1024

maximumPoetryClosureFiles :: Integer
maximumPoetryClosureFiles = 100000

maximumPoetryClosureCount :: Int
maximumPoetryClosureCount = 16

maximumPoetryClosureDepth :: Int
maximumPoetryClosureDepth = 64

digestPackageClosure ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  FilePath ->
  Int ->
  (Integer, Integer, SHA256.Ctx) ->
  IO (Integer, Integer, SHA256.Ctx)
digestPackageClosure
  excludeBaseSitePackages
  closureRoot
  directoryPath
  directoryDescriptor
  listedStatus
  relativePath
  depth
  state = do
    unless
      (depth <= maximumPoetryClosureDepth)
      (ioError (userError "Poetry package closure exceeds its fixed depth bound"))
    unless
      (Posix.isDirectory listedStatus)
      (ioError (userError ("Poetry closure entry is not a real directory: " <> directoryPath)))
    entries <-
      listDirectoryBoundedFromDescriptor
        directoryDescriptor
        ( maximumPoetryClosureFiles
            - closureFiles state
        )
    let directoryContext =
          updateClosureDigest
            (closureDigestContext state)
            ("D\NUL" <> relativePath <> "\NUL")
    observed <-
      foldM
        ( digestPackageClosureEntry
            excludeBaseSitePackages
            closureRoot
            directoryPath
            directoryDescriptor
            relativePath
            depth
        )
        (closureBytes state, closureFiles state, directoryContext)
        entries
    finalStatus <- Posix.getFdStatus directoryDescriptor
    unless
      (stableExecutableStatus listedStatus finalStatus)
      (ioError (userError ("Poetry closure directory changed while hashing: " <> directoryPath)))
    pure observed

digestPackageClosureEntry ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  Int ->
  (Integer, Integer, SHA256.Ctx) ->
  FilePath ->
  IO (Integer, Integer, SHA256.Ctx)
digestPackageClosureEntry
  excludeBaseSitePackages
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
      Right descriptor ->
        finallyPreservingPrimary
          ( do
              status <- Posix.getFdStatus descriptor
              unless
                (Posix.isDirectory status)
                (ioError (userError ("Poetry closure child is not a directory: " <> path)))
              let nextEntries = closureFiles state + 1
              unless
                (nextEntries <= maximumPoetryClosureFiles)
                (ioError (userError "Poetry package closure exceeds its fixed entry bound"))
              observed <-
                digestPackageClosure
                  excludeBaseSitePackages
                  closureRoot
                  path
                  descriptor
                  status
                  relativePath
                  (parentDepth + 1)
                  (closureBytes state, nextEntries, closureDigestContext state)
              finalStatus <- Posix.getFdStatus descriptor
              reopenedStatus <- reopenDirectoryEntryStatus parentDescriptor entry
              unless
                ( stableExecutableStatus status finalStatus
                    && stableExecutableStatus finalStatus reopenedStatus
                )
                (ioError (userError ("Poetry closure directory entry changed: " <> path)))
              pure observed
          )
          (closeFd descriptor)
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
              (digestPackageClosureFile parentDescriptor entry path descriptor relativePath state)
              (closeFd descriptor)
          Left _ ->
            digestPackageClosureLink
              excludeBaseSitePackages
              closureRoot
              parentDescriptor
              parentPath
              path
              relativePath
              state

digestPackageClosureFile ::
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  (Integer, Integer, SHA256.Ctx) ->
  IO (Integer, Integer, SHA256.Ctx)
digestPackageClosureFile
  parentDescriptor
  entry
  path
  descriptor
  relativePath
  state = do
    status <- Posix.getFdStatus descriptor
    unless
      (Posix.isRegularFile status)
      (ioError (userError ("Poetry closure entry is unsupported: " <> path)))
    let fileBytes = fromIntegral (Posix.fileSize status)
        nextBytes = closureBytes state + fileBytes
        nextFiles = closureFiles state + 1
    unless
      ( fileBytes <= maximumExactRuntimeFileBytes
          && nextBytes <= maximumPoetryClosureBytes
          && nextFiles <= maximumPoetryClosureFiles
      )
      (ioError (userError "Poetry package closure exceeds its fixed size bound"))
    digest <- digestExactProvisioningDescriptor descriptor fileBytes
    finalStatus <- Posix.getFdStatus descriptor
    reopenedStatus <- reopenFileEntryStatus parentDescriptor entry
    unless
      ( stableExecutableStatus status finalStatus
          && stableExecutableStatus finalStatus reopenedStatus
      )
      (ioError (userError ("Poetry package closure file changed while hashing: " <> path)))
    let executableFlag =
          if Posix.fileMode status
            .&. ( Posix.ownerExecuteMode
                    .|. Posix.groupExecuteMode
                    .|. Posix.otherExecuteMode
                )
            /= 0
            then "X"
            else "F"
        context =
          updateClosureDigest
            (closureDigestContext state)
            ( executableFlag
                <> "\NUL"
                <> relativePath
                <> "\NUL"
                <> show (Posix.fileSize status)
                <> "\NUL"
                <> Text.unpack digest
                <> "\NUL"
            )
    pure (nextBytes, nextFiles, context)

digestPackageClosureLink ::
  Bool ->
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  FilePath ->
  (Integer, Integer, SHA256.Ctx) ->
  IO (Integer, Integer, SHA256.Ctx)
digestPackageClosureLink
  excludeBaseSitePackages
  _closureRoot
  parentDescriptor
  parentPath
  path
  relativePath
  state = do
    parentStatus <- Posix.getFdStatus parentDescriptor
    parentPathStatus <- Posix.getSymbolicLinkStatus parentPath
    unless
      (stableExecutableStatus parentStatus parentPathStatus)
      (ioError (userError ("Poetry closure link parent changed: " <> parentPath)))
    status <- Posix.getSymbolicLinkStatus path
    unless
      (Posix.isSymbolicLink status)
      (ioError (userError ("Poetry closure entry is neither openable nor a symlink: " <> path)))
    linkTarget <- Posix.readSymbolicLink path
    finalStatus <- Posix.getSymbolicLinkStatus path
    finalTarget <- Posix.readSymbolicLink path
    finalParentStatus <- Posix.getFdStatus parentDescriptor
    finalParentPathStatus <- Posix.getSymbolicLinkStatus parentPath
    unless
      ( stableExecutableStatus status finalStatus
          && linkTarget == finalTarget
          && stableExecutableStatus parentStatus finalParentStatus
          && stableExecutableStatus finalParentStatus finalParentPathStatus
      )
      (ioError (userError ("Poetry package closure link changed: " <> path)))
    if excludeBaseSitePackages
      && excludedPythonBaseSitePackagesLink relativePath
      then pure state
      else do
        let linkBytes =
              fromIntegral
                ( ByteString.length
                    (TextEncoding.encodeUtf8 (Text.pack linkTarget))
                )
            nextBytes = closureBytes state + linkBytes
            nextFiles = closureFiles state + 1
        unless
          ( validRelativeClosureLink relativePath linkTarget
              && nextBytes <= maximumPoetryClosureBytes
              && nextFiles <= maximumPoetryClosureFiles
          )
          (ioError (userError ("Poetry package closure has an unsafe link: " <> path)))
        pure
          ( nextBytes,
            nextFiles,
            updateClosureDigest
              (closureDigestContext state)
              ( "L\NUL"
                  <> relativePath
                  <> "\NUL"
                  <> linkTarget
                  <> "\NUL"
              )
          )

validRelativeClosureLink :: FilePath -> FilePath -> Bool
validRelativeClosureLink relativePath linkTarget =
  not (isAbsolute linkTarget)
    && '\NUL' `notElem` linkTarget
    && case splitDirectories
      (normalise (takeDirectory relativePath </> linkTarget)) of
      ".." : _ -> False
      _ -> True

excludedPythonBaseSitePackagesLink :: FilePath -> Bool
excludedPythonBaseSitePackagesLink relativePath =
  case splitDirectories (normalise relativePath) of
    ["lib", pythonDirectory, "site-packages"] ->
      "python" `List.isPrefixOf` pythonDirectory
    _ -> False

closureBytes :: (Integer, Integer, SHA256.Ctx) -> Integer
closureBytes (bytes, _, _) = bytes

closureFiles :: (Integer, Integer, SHA256.Ctx) -> Integer
closureFiles (_, files, _) = files

closureDigestContext ::
  (Integer, Integer, SHA256.Ctx) ->
  SHA256.Ctx
closureDigestContext (_, _, context) = context

updateClosureDigest :: SHA256.Ctx -> String -> SHA256.Ctx
updateClosureDigest context =
  SHA256.update context . TextEncoding.encodeUtf8 . Text.pack

copyExactPackageClosure ::
  EngineWriter w s q ->
  Internal.ProvisioningPackageClosureIdentity ->
  FilePath ->
  ProvisioningSession s InstalledRuntimeSource
copyExactPackageClosure
  (EngineWriter _ _ authorizedRoot)
  expectedSource
  requestedDestination =
    ProvisioningSession $ mask $ \restore -> do
      destination <-
        authorizedWriterPath
          "fixed runtime closure destination"
          authorizedRoot
          requestedDestination
      prepareEmptyClosureDestination destination
      let source =
            Internal.provisioningPackageClosureRoot expectedSource
          role =
            Internal.provisioningPackageClosureRole expectedSource
          excludeBaseSitePackages =
            role == Internal.ProvisioningPythonHomeClosure
      observedSource <- resolvePackageClosureIdentity role source
      unless
        (observedSource == expectedSource)
        (ioError (userError "fixed runtime closure source changed before materialization"))
      sourceDescriptor <-
        openFd
          source
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              directory = True,
              cloexec = True
            }
      finallyPreservingPrimary
        ( restore $ do
            openedSourceStatus <- Posix.getFdStatus sourceDescriptor
            unless
              (packageClosureRootStatusMatches expectedSource openedSourceStatus)
              (ioError (userError "fixed runtime closure source changed before descriptor copy"))
            copyPackageClosureDirectory
              excludeBaseSitePackages
              source
              destination
              sourceDescriptor
              openedSourceStatus
              "."
              0
              0
            finalSourceStatus <- Posix.getFdStatus sourceDescriptor
            finalSourcePathStatus <- Posix.getSymbolicLinkStatus source
            unless
              ( stableExecutableStatus openedSourceStatus finalSourceStatus
                  && stableExecutableStatus
                    finalSourceStatus
                    finalSourcePathStatus
              )
              (ioError (userError "fixed runtime closure source changed during materialization"))
        )
        (closeFd sourceDescriptor)
      finalSource <- resolvePackageClosureIdentity role source
      installed <- resolvePackageClosureIdentity role destination
      unless
        ( finalSource == expectedSource
            && packageClosurePayloadMatches expectedSource installed
        )
        (ioError (userError "fixed runtime closure copy disagreed with its exact source"))
      validateWriterRootIdentity
        "fixed runtime closure materialization"
        authorizedRoot
      pure
        InstalledRuntimeSource
          { installedRuntimeSourcePath = source,
            installedRuntimeOwnedPath = destination,
            installedRuntimeSourceDigest =
              Internal.provisioningPackageClosureDigest installed,
            installedRuntimeSourceFiles =
              Internal.provisioningPackageClosureFiles installed,
            installedRuntimeSourceBytes =
              Internal.provisioningPackageClosureBytes installed
          }

packageClosurePayloadMatches ::
  Internal.ProvisioningPackageClosureIdentity ->
  Internal.ProvisioningPackageClosureIdentity ->
  Bool
packageClosurePayloadMatches expected observed =
  Internal.provisioningPackageClosureRole observed
    == Internal.provisioningPackageClosureRole expected
    && Internal.provisioningPackageClosureBytes observed
      == Internal.provisioningPackageClosureBytes expected
    && Internal.provisioningPackageClosureFiles observed
      == Internal.provisioningPackageClosureFiles expected
    && Internal.provisioningPackageClosureDigest observed
      == Internal.provisioningPackageClosureDigest expected

prepareEmptyClosureDestination :: FilePath -> IO ()
prepareEmptyClosureDestination destination = do
  observed <- try @IOException (Posix.getSymbolicLinkStatus destination)
  case observed of
    Left failure
      | isDoesNotExistError failure ->
          Directory.createDirectory destination
      | otherwise -> throwIO failure
    Right listedStatus -> do
      unless
        ( Posix.isDirectory listedStatus
            && not (Posix.isSymbolicLink listedStatus)
        )
        (ioError (userError "fixed runtime closure destination is not a real directory"))
      descriptor <-
        openFd
          destination
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              directory = True,
              cloexec = True
            }
      finallyPreservingPrimary
        ( do
            openedStatus <- Posix.getFdStatus descriptor
            entries <- listDirectoryBoundedFromDescriptor descriptor 1
            finalStatus <- Posix.getFdStatus descriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus destination
            unless
              ( null entries
                  && stableExecutableStatus listedStatus openedStatus
                  && stableExecutableStatus openedStatus finalStatus
                  && stableExecutableStatus finalStatus finalPathStatus
              )
              (ioError (userError "fixed runtime closure destination is not stably empty"))
        )
        (closeFd descriptor)

copyPackageClosureDirectory ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  FilePath ->
  Int ->
  Integer ->
  IO Integer
copyPackageClosureDirectory
  excludeBaseSitePackages
  sourceDirectory
  destinationDirectory
  sourceDescriptor
  listedSourceStatus
  relativeDirectory
  depth
  entriesSeen = do
    unless
      (depth <= maximumPoetryClosureDepth)
      (ioError (userError "fixed runtime closure copy exceeded its depth bound"))
    entries <-
      listDirectoryBoundedFromDescriptor
        sourceDescriptor
        (maximumPoetryClosureFiles - entriesSeen)
    finalEntries <-
      foldM
        ( copyPackageClosureEntry
            excludeBaseSitePackages
            sourceDirectory
            destinationDirectory
            sourceDescriptor
            relativeDirectory
            depth
        )
        entriesSeen
        entries
    finalSourceStatus <- Posix.getFdStatus sourceDescriptor
    unless
      (stableExecutableStatus listedSourceStatus finalSourceStatus)
      (ioError (userError "fixed runtime closure directory changed during copy"))
    synchroniseProvisioningDirectory destinationDirectory
    pure finalEntries

copyPackageClosureEntry ::
  Bool ->
  FilePath ->
  FilePath ->
  Fd ->
  FilePath ->
  Int ->
  Integer ->
  FilePath ->
  IO Integer
copyPackageClosureEntry
  excludeBaseSitePackages
  sourceDirectory
  destinationDirectory
  sourceParentDescriptor
  parentRelative
  parentDepth
  entriesSeen
  entry = do
    let source = sourceDirectory </> entry
        destination = destinationDirectory </> entry
        relativePath =
          if parentRelative == "."
            then entry
            else parentRelative </> entry
        nextEntries = entriesSeen + 1
    unless
      (nextEntries <= maximumPoetryClosureFiles)
      (ioError (userError "fixed runtime closure copy exceeded its entry bound"))
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
      Right childDescriptor ->
        finallyPreservingPrimary
          ( do
              childStatus <- Posix.getFdStatus childDescriptor
              unless
                (Posix.isDirectory childStatus)
                (ioError (userError "fixed runtime closure child is not a directory"))
              Directory.createDirectory destination
              copied <-
                copyPackageClosureDirectory
                  excludeBaseSitePackages
                  source
                  destination
                  childDescriptor
                  childStatus
                  relativePath
                  (parentDepth + 1)
                  nextEntries
              reopenedStatus <-
                reopenDirectoryEntryStatus sourceParentDescriptor entry
              finalChildStatus <- Posix.getFdStatus childDescriptor
              unless
                ( stableExecutableStatus childStatus finalChildStatus
                    && stableExecutableStatus finalChildStatus reopenedStatus
                )
                (ioError (userError "fixed runtime closure directory entry changed"))
              pure copied
          )
          (closeFd childDescriptor)
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
          Right sourceFileDescriptor ->
            finallyPreservingPrimary
              ( do
                  sourceFileStatus <- Posix.getFdStatus sourceFileDescriptor
                  unless
                    (Posix.isRegularFile sourceFileStatus)
                    (ioError (userError "fixed runtime closure entry is unsupported"))
                  _ <-
                    copyRegularFileStable
                      maximumExactRuntimeFileBytes
                      source
                      destination
                  finalFileStatus <- Posix.getFdStatus sourceFileDescriptor
                  reopenedStatus <-
                    reopenFileEntryStatus sourceParentDescriptor entry
                  unless
                    ( stableExecutableStatus sourceFileStatus finalFileStatus
                        && stableExecutableStatus finalFileStatus reopenedStatus
                    )
                    (ioError (userError "fixed runtime closure file changed during copy"))
                  pure nextEntries
              )
              (closeFd sourceFileDescriptor)
          Left _ ->
            copyPackageClosureLink
              excludeBaseSitePackages
              sourceParentDescriptor
              sourceDirectory
              source
              destination
              relativePath
              nextEntries

copyPackageClosureLink ::
  Bool ->
  Fd ->
  FilePath ->
  FilePath ->
  FilePath ->
  FilePath ->
  Integer ->
  IO Integer
copyPackageClosureLink
  excludeBaseSitePackages
  sourceParentDescriptor
  sourceParent
  source
  destination
  relativePath
  nextEntries = do
    parentStatus <- Posix.getFdStatus sourceParentDescriptor
    parentPathStatus <- Posix.getSymbolicLinkStatus sourceParent
    sourceStatus <- Posix.getSymbolicLinkStatus source
    unless
      ( stableExecutableStatus parentStatus parentPathStatus
          && Posix.isSymbolicLink sourceStatus
      )
      (ioError (userError "fixed runtime closure link source is invalid"))
    target <- Posix.readSymbolicLink source
    if excludeBaseSitePackages
      && excludedPythonBaseSitePackagesLink relativePath
      then pure nextEntries
      else do
        unless
          (validRelativeClosureLink relativePath target)
          (ioError (userError "fixed runtime closure link escapes its source root"))
        Posix.createSymbolicLink target destination
        installedStatus <- Posix.getSymbolicLinkStatus destination
        installedTarget <- Posix.readSymbolicLink destination
        finalSourceStatus <- Posix.getSymbolicLinkStatus source
        finalSourceTarget <- Posix.readSymbolicLink source
        finalParentStatus <- Posix.getFdStatus sourceParentDescriptor
        finalParentPathStatus <- Posix.getSymbolicLinkStatus sourceParent
        unless
          ( Posix.isSymbolicLink installedStatus
              && installedTarget == target
              && stableExecutableStatus sourceStatus finalSourceStatus
              && finalSourceTarget == target
              && stableExecutableStatus parentStatus finalParentStatus
              && stableExecutableStatus finalParentStatus finalParentPathStatus
          )
          (ioError (userError "fixed runtime closure link changed during copy"))
        synchroniseProvisioningDirectory (takeDirectory destination)
        pure nextEntries

materializePythonFrameworkLinks ::
  EngineWriter w s q ->
  FilePath ->
  FilePath ->
  FilePath ->
  ProvisioningSession s [InstalledRuntimeSource]
materializePythonFrameworkLinks
  writer
  candidateRoot
  sourcePythonHome
  installedPythonHome = do
    let version = takeFileName sourcePythonHome
        frameworkRoot =
          candidateRoot
            </> "python-frameworks"
            </> "Python.framework"
        versionsRoot = frameworkRoot </> "Versions"
    unless
      ( validFixedPathComponent version
          && normalise installedPythonHome
            == normalise (candidateRoot </> "python-home")
      )
      (failProvisioningSession "resolved Python home has an unsafe framework version")
    createFixedOwnedDirectoryTree writer candidateRoot versionsRoot
    versionSource <-
      createFixedOwnedLink
        writer
        (versionsRoot </> version)
        (".." </> ".." </> ".." </> "python-home")
    currentSource <-
      createFixedOwnedLink
        writer
        (versionsRoot </> "Current")
        version
    pythonSource <-
      createFixedOwnedLink
        writer
        (frameworkRoot </> "Python")
        ("Versions" </> "Current" </> "Python")
    resourcesPresent <-
      provisioningDoesDirectoryExist (installedPythonHome </> "Resources")
    resourcesSources <-
      if resourcesPresent
        then
          (: [])
            <$> createFixedOwnedLink
              writer
              (frameworkRoot </> "Resources")
              ("Versions" </> "Current" </> "Resources")
        else pure []
    pure
      (versionSource : currentSource : pythonSource : resourcesSources)

validFixedPathComponent :: FilePath -> Bool
validFixedPathComponent component =
  not (null component)
    && component /= "."
    && component /= ".."
    && component == takeFileName component
    && '\NUL' `notElem` component

createFixedOwnedDirectoryTree ::
  EngineWriter w s q ->
  FilePath ->
  FilePath ->
  ProvisioningSession s ()
createFixedOwnedDirectoryTree writer root requestedDirectory = do
  authorizedRoot <-
    authorizeEnginePath "fixed runtime directory root" writer root
  authorizedDirectory <-
    authorizeEnginePath
      "fixed runtime directory"
      writer
      requestedDirectory
  let relativeDirectory =
        makeRelative authorizedRoot authorizedDirectory
      components =
        filter
          (\component -> component /= "." && component /= "/")
          (splitDirectories relativeDirectory)
  unless
    ( not (null components)
        && not (isAbsolute relativeDirectory)
        && ".." `notElem` components
    )
    (failProvisioningSession "fixed runtime directory escaped its candidate root")
  foldM_
    ( \parent component -> do
        let child = parent </> component
        createFixedOwnedDirectory writer child
        pure child
    )
    authorizedRoot
    components

createFixedOwnedDirectory ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
createFixedOwnedDirectory
  (EngineWriter _ _ authorizedRoot)
  requestedDirectory =
    ProvisioningSession $ do
      directory <-
        authorizedWriterPath
          "fixed runtime directory"
          authorizedRoot
          requestedDirectory
      observed <- try @IOException (Posix.getSymbolicLinkStatus directory)
      case observed of
        Left failure
          | isDoesNotExistError failure ->
              Directory.createDirectory directory
          | otherwise -> throwIO failure
        Right status ->
          unless
            ( Posix.isDirectory status
                && not (Posix.isSymbolicLink status)
            )
            (ioError (userError "fixed runtime directory is not a real directory"))
      finalStatus <- Posix.getSymbolicLinkStatus directory
      unless
        (Posix.isDirectory finalStatus && not (Posix.isSymbolicLink finalStatus))
        (ioError (userError "fixed runtime directory publication is invalid"))
      synchroniseProvisioningDirectory (takeDirectory directory)
      validateWriterRootIdentity "fixed runtime directory" authorizedRoot

createFixedOwnedLink ::
  EngineWriter w s q ->
  FilePath ->
  FilePath ->
  ProvisioningSession s InstalledRuntimeSource
createFixedOwnedLink
  (EngineWriter _ _ authorizedRoot)
  requestedLink
  target =
    ProvisioningSession $ do
      link <-
        authorizedWriterPath
          "fixed runtime link"
          authorizedRoot
          requestedLink
      let relativeLink =
            makeRelative
              (authorizedWriterCanonicalRoot authorizedRoot)
              link
      unless
        (validRelativeClosureLink relativeLink target)
        (ioError (userError "fixed runtime link escapes its artifact root"))
      Posix.createSymbolicLink target link
      status <- Posix.getSymbolicLinkStatus link
      observedTarget <- Posix.readSymbolicLink link
      unless
        (Posix.isSymbolicLink status && observedTarget == target)
        (ioError (userError "fixed runtime link publication disagreed"))
      synchroniseProvisioningDirectory (takeDirectory link)
      validateWriterRootIdentity "fixed runtime link" authorizedRoot
      let encodedTarget =
            TextEncoding.encodeUtf8 (Text.pack target)
      pure
        InstalledRuntimeSource
          { installedRuntimeSourcePath = "relative-link:" <> target,
            installedRuntimeOwnedPath = link,
            installedRuntimeSourceDigest =
              "sha256:"
                <> TextEncoding.decodeUtf8
                  (Base16.encode (SHA256.hash encodedTarget)),
            installedRuntimeSourceFiles = 1,
            installedRuntimeSourceBytes =
              fromIntegral (ByteString.length encodedTarget)
          }

materializeRuntimeLibraries ::
  EngineWriter w s q ->
  FilePath ->
  [FilePath] ->
  [Internal.ProvisioningRuntimeLibraryIdentity] ->
  ProvisioningSession s [InstalledRuntimeSource]
materializeRuntimeLibraries
  writer
  candidateRoot
  coveredRoots
  libraries = do
    let uncovered =
          [ library
          | library <- libraries,
            let source =
                  Internal.provisioningRuntimeLibraryCanonicalPath library,
            not
              ( any
                  (`writerPathWithin` source)
                  coveredRoots
              )
          ]
        destinations =
          [ runtimeLibraryDestination candidateRoot library
          | library <- uncovered
          ]
    unless
      (length destinations == length (List.nub (map normalise destinations)))
      (failProvisioningSession "fixed Mach-O closure has an owned-path collision")
    zipWithM
      (copyRuntimeLibraryFile writer candidateRoot)
      uncovered
      destinations

runtimeLibraryDestination ::
  FilePath ->
  Internal.ProvisioningRuntimeLibraryIdentity ->
  FilePath
runtimeLibraryDestination candidateRoot library =
  case frameworkRelativeSuffix
    (Internal.provisioningRuntimeLibraryCanonicalPath library) of
    Just relativeFrameworkPath ->
      candidateRoot
        </> "native"
        </> "frameworks"
        </> relativeFrameworkPath
    Nothing ->
      candidateRoot
        </> "native"
        </> "lib"
        </> Internal.provisioningRuntimeLibraryLeafName library

frameworkRelativeSuffix :: FilePath -> Maybe FilePath
frameworkRelativeSuffix path =
  search (splitDirectories (normalise path))
  where
    search components =
      case components of
        [] -> Nothing
        component : remaining
          | ".framework" `List.isSuffixOf` component
              && validFixedPathComponent component
              && all validFixedPathComponent remaining ->
              Just (joinPath (component : remaining))
          | otherwise -> search remaining

copyResolvedExecutableFile ::
  EngineWriter w s q ->
  FilePath ->
  ResolvedExecutableIdentity ->
  FilePath ->
  ProvisioningSession s InstalledRuntimeSource
copyResolvedExecutableFile
  writer
  candidateRoot
  expected
  requestedDestination = do
    createFixedOwnedDirectoryTree
      writer
      candidateRoot
      (takeDirectory requestedDestination)
    let EngineWriter _ _ authorizedRoot = writer
    ProvisioningSession $ do
      destination <-
        authorizedWriterPath
          "fixed executable destination"
          authorizedRoot
          requestedDestination
      observed <-
        resolveExactExecutableIdentity
          (resolvedExecutableCanonicalPath expected)
      unless
        (resolvedExecutableIdentityMatches expected observed)
        (ioError (userError "fixed executable source changed before copy"))
      copied <-
        copyRegularFileStable
          maximumExactRuntimeFileBytes
          (resolvedExecutableCanonicalPath expected)
          destination
      finalObserved <-
        resolveExactExecutableIdentity
          (resolvedExecutableCanonicalPath expected)
      unless
        ( resolvedExecutableIdentityMatches expected finalObserved
            && stableFileCopyDigest copied
              == resolvedExecutableDigest expected
            && fromIntegral
              (provisioningPathFileSize (stableFileCopyInfo copied))
              == Posix.fileSize
                (resolvedExecutableCanonicalStatus expected)
        )
        (ioError (userError "fixed executable copy disagreed with its exact source"))
      validateWriterRootIdentity "fixed executable copy" authorizedRoot
      pure
        InstalledRuntimeSource
          { installedRuntimeSourcePath =
              resolvedExecutableCanonicalPath expected,
            installedRuntimeOwnedPath = destination,
            installedRuntimeSourceDigest =
              resolvedExecutableDigest expected,
            installedRuntimeSourceFiles = 1,
            installedRuntimeSourceBytes =
              fromIntegral
                (Posix.fileSize (resolvedExecutableCanonicalStatus expected))
          }

copyRuntimeLibraryFile ::
  EngineWriter w s q ->
  FilePath ->
  Internal.ProvisioningRuntimeLibraryIdentity ->
  FilePath ->
  ProvisioningSession s InstalledRuntimeSource
copyRuntimeLibraryFile
  writer
  candidateRoot
  expected
  requestedDestination = do
    createFixedOwnedDirectoryTree
      writer
      candidateRoot
      (takeDirectory requestedDestination)
    let EngineWriter _ _ authorizedRoot = writer
    ProvisioningSession $ do
      destination <-
        authorizedWriterPath
          "fixed runtime library destination"
          authorizedRoot
          requestedDestination
      observed <-
        resolveExactExecutableIdentity
          (Internal.provisioningRuntimeLibraryCanonicalPath expected)
      unless
        (resolvedIdentityMatchesRuntimeIdentity observed expected)
        (ioError (userError "fixed runtime library changed before copy"))
      copied <-
        copyRegularFileStable
          maximumExactRuntimeFileBytes
          (Internal.provisioningRuntimeLibraryCanonicalPath expected)
          destination
      finalObserved <-
        resolveExactExecutableIdentity
          (Internal.provisioningRuntimeLibraryCanonicalPath expected)
      unless
        ( resolvedIdentityMatchesRuntimeIdentity finalObserved expected
            && stableFileCopyDigest copied
              == Internal.provisioningRuntimeLibraryDigest expected
            && fromIntegral
              (provisioningPathFileSize (stableFileCopyInfo copied))
              == Internal.provisioningRuntimeLibrarySize expected
        )
        (ioError (userError "fixed runtime library copy disagreed with its exact source"))
      validateWriterRootIdentity "fixed runtime library copy" authorizedRoot
      pure
        InstalledRuntimeSource
          { installedRuntimeSourcePath =
              Internal.provisioningRuntimeLibraryCanonicalPath expected,
            installedRuntimeOwnedPath = destination,
            installedRuntimeSourceDigest =
              Internal.provisioningRuntimeLibraryDigest expected,
            installedRuntimeSourceFiles = 1,
            installedRuntimeSourceBytes =
              Internal.provisioningRuntimeLibrarySize expected
          }

discoverGgmlPluginRoots :: [FilePath] -> IO [FilePath]
discoverGgmlPluginRoots paths = do
  let candidates =
        List.nub
          (List.sort (foldr maybeGgmlRoot [] paths))
  filterMRealDirectory candidates
  where
    maybeGgmlRoot path roots =
      case homebrewGgmlLibexecRoot path of
        Nothing -> roots
        Just root -> root : roots

    filterMRealDirectory candidates =
      case candidates of
        [] -> pure []
        candidate : remaining -> do
          observed <-
            try @IOException
              (Posix.getSymbolicLinkStatus candidate)
          rest <- filterMRealDirectory remaining
          case observed of
            Right status
              | Posix.isDirectory status
                  && not (Posix.isSymbolicLink status) ->
                  pure (candidate : rest)
            Right _ ->
              ioError
                (userError "ggml libexec closure root is not a real directory")
            Left failure
              | isDoesNotExistError failure -> pure rest
              | otherwise -> throwIO failure

homebrewGgmlLibexecRoot :: FilePath -> Maybe FilePath
homebrewGgmlLibexecRoot path =
  search [] (splitDirectories (normalise path))
  where
    search prefix components =
      case components of
        "Cellar" : "ggml" : version : _
          | validFixedPathComponent version ->
              Just
                ( joinPath
                    (prefix <> ["Cellar", "ggml", version, "libexec"])
                )
        component : remaining ->
          search (prefix <> [component]) remaining
        [] -> Nothing

installedRuntimeEvidence ::
  FilePath ->
  [InstalledRuntimeSource] ->
  ProvisioningSession s (InstalledMachORuntimeClosure s)
installedRuntimeEvidence root sources = do
  let ordered =
        List.sortOn
          (\source -> (installedRuntimeOwnedPath source, installedRuntimeSourcePath source))
          sources
      fileCount =
        sum (map installedRuntimeSourceFiles ordered)
      byteCount =
        sum (map installedRuntimeSourceBytes ordered)
      digestContext =
        foldl
          hashInstalledRuntimeSource
          (SHA256.update SHA256.init "infernix-installed-runtime-v1\NUL")
          ordered
  unless
    ( not (null ordered)
        && fileCount >= 1
        && fileCount <= fromIntegral (maxBound :: Int)
        && byteCount >= 0
        && byteCount <= 8 * 1024 * 1024 * 1024
    )
    (failProvisioningSession "installed runtime evidence exceeds its fixed bound")
  pure
    InstalledMachORuntimeClosure
      { installedMachORuntimeClosureRoot = root,
        installedMachORuntimeClosureFiles = fromIntegral fileCount,
        installedMachORuntimeClosureBytes = byteCount,
        installedMachORuntimeClosureDigest =
          "sha256:"
            <> TextEncoding.decodeUtf8
              (Base16.encode (SHA256.finalize digestContext)),
        installedMachORuntimeClosureSources = ordered
      }

hashInstalledRuntimeSource ::
  SHA256.Ctx ->
  InstalledRuntimeSource ->
  SHA256.Ctx
hashInstalledRuntimeSource context source =
  SHA256.update
    context
    ( TextEncoding.encodeUtf8
        ( Text.intercalate
            "\NUL"
            [ Text.pack (installedRuntimeSourcePath source),
              Text.pack (installedRuntimeOwnedPath source),
              installedRuntimeSourceDigest source,
              Text.pack (show (installedRuntimeSourceFiles source)),
              Text.pack (show (installedRuntimeSourceBytes source)),
              ""
            ]
        )
    )

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
            (closeFd descriptor)
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

reopenDirectoryEntryStatus :: Fd -> FilePath -> IO Posix.FileStatus
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
      (restore (Posix.getFdStatus descriptor))
      (closeFd descriptor)

reopenFileEntryStatus :: Fd -> FilePath -> IO Posix.FileStatus
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
          status <- Posix.getFdStatus descriptor
          unless
            (Posix.isRegularFile status)
            (ioError (userError "reopened package entry is not regular"))
          pure status
      )
      (closeFd descriptor)

digestExactProvisioningDescriptor :: Fd -> Integer -> IO Text
digestExactProvisioningDescriptor descriptor expectedBytes =
  go 0 SHA256.init
  where
    go observedBytes context
      | observedBytes > expectedBytes =
          ioError (userError "package descriptor exceeded its exact byte bound")
      | otherwise = do
          let remaining = expectedBytes - observedBytes
              requested =
                fromIntegral (min (64 * 1024) (remaining + 1))
          chunk <- PosixByteString.fdRead descriptor requested
          if ByteString.null chunk
            then do
              unless
                (observedBytes == expectedBytes)
                (ioError (userError "package descriptor ended before its exact byte bound"))
              pure
                ( "sha256:"
                    <> TextEncoding.decodeUtf8
                      (Base16.encode (SHA256.finalize context))
                )
            else do
              let nextBytes =
                    observedBytes
                      + fromIntegral (ByteString.length chunk)
              unless
                (nextBytes <= expectedBytes)
                (ioError (userError "package descriptor grew beyond its exact byte bound"))
              go nextBytes (SHA256.update context chunk)

readExactProvisioningDescriptorBytes ::
  Fd ->
  Integer ->
  IO ByteString.ByteString
readExactProvisioningDescriptorBytes descriptor expectedBytes
  | expectedBytes < 0
      || expectedBytes > fromIntegral (maxBound :: Int) =
      ioError (userError "exact descriptor byte count is invalid")
  | otherwise =
      go 0 []
  where
    go observedBytes chunks
      | observedBytes > expectedBytes =
          ioError (userError "exact descriptor read exceeded its bound")
      | otherwise = do
          let remaining = expectedBytes - observedBytes
              requested =
                fromIntegral (min (64 * 1024) (remaining + 1))
          chunk <- PosixByteString.fdRead descriptor requested
          if ByteString.null chunk
            then do
              unless
                (observedBytes == expectedBytes)
                (ioError (userError "exact descriptor read ended early"))
              pure (ByteString.concat (reverse chunks))
            else do
              let nextBytes =
                    observedBytes
                      + fromIntegral (ByteString.length chunk)
              unless
                (nextBytes <= expectedBytes)
                (ioError (userError "exact descriptor read observed growth"))
              go nextBytes (chunk : chunks)

listDirectoryBoundedNoFollow ::
  FilePath ->
  Posix.FileStatus ->
  Integer ->
  IO [FilePath]
listDirectoryBoundedNoFollow path expectedStatus maximumEntries
  | maximumEntries < 0 =
      ioError (userError "directory entry budget is already exhausted")
  | otherwise =
      mask $ \restore -> do
        descriptor <-
          openFd
            path
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        _ <-
          onExceptionPreservingPrimary
            ( do
                openedStatus <- Posix.getFdStatus descriptor
                unless
                  ( Posix.isDirectory openedStatus
                      && stableExecutableStatus
                        expectedStatus
                        openedStatus
                  )
                  (ioError (userError ("directory changed before descriptor enumeration: " <> path)))
                pure openedStatus
            )
            (closeFd descriptor)
        stream <-
          onExceptionPreservingPrimary
            (unsafeOpenDirStreamFd descriptor)
            (closeFd descriptor)
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
                (ioError (userError ("directory exceeds its fixed entry budget: " <> path)))
              readEntries stream nextObserved (entry : entries)

revalidateExecutableIdentity ::
  ResolvedExecutableIdentity ->
  IO (Either String ())
revalidateExecutableIdentity expected = do
  result <-
    try @IOException $ do
      configuredStatus <-
        Posix.getSymbolicLinkStatus
          (resolvedExecutableConfiguredPath expected)
      canonicalPath <-
        Directory.canonicalizePath
          (resolvedExecutableConfiguredPath expected)
      canonicalStatus <- Posix.getSymbolicLinkStatus canonicalPath
      (stableCanonicalStatus, digest) <-
        digestExecutable canonicalPath canonicalStatus
      if
        | canonicalPath /= resolvedExecutableCanonicalPath expected ->
            pure (Left "configured executable canonical target changed")
        | not
            ( stableExecutableStatus
                (resolvedExecutableConfiguredStatus expected)
                configuredStatus
            ) ->
            pure (Left "configured executable path identity changed")
        | not
            ( stableExecutableStatus
                (resolvedExecutableCanonicalStatus expected)
                stableCanonicalStatus
            ) ->
            pure (Left "configured executable target identity changed")
        | digest /= resolvedExecutableDigest expected ->
            pure (Left "configured executable content digest changed")
        | otherwise -> pure (Right ())
  pure
    ( case result of
        Left failure -> Left (displayException failure)
        Right validation -> validation
    )

stableExecutableStatus :: Posix.FileStatus -> Posix.FileStatus -> Bool
stableExecutableStatus expected observed =
  Posix.deviceID expected == Posix.deviceID observed
    && Posix.fileID expected == Posix.fileID observed
    && Posix.fileMode expected == Posix.fileMode observed
    && Posix.fileSize expected == Posix.fileSize observed
    && Posix.modificationTimeHiRes expected
      == Posix.modificationTimeHiRes observed
    && Posix.statusChangeTimeHiRes expected
      == Posix.statusChangeTimeHiRes observed

digestExecutable ::
  FilePath ->
  Posix.FileStatus ->
  IO (Posix.FileStatus, Text)
digestExecutable path listedStatus =
  digestExecutableWithObserver path listedStatus (pure ())

digestExecutableWithObserver ::
  FilePath ->
  Posix.FileStatus ->
  IO () ->
  IO (Posix.FileStatus, Text)
digestExecutableWithObserver path listedStatus observeOpened =
  mask $ \restore -> do
    descriptor <-
      openFd
        path
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( do
          openedStatus <- Posix.getFdStatus descriptor
          if Posix.isRegularFile openedStatus
            && not (Posix.isSymbolicLink openedStatus)
            && stableExecutableStatus listedStatus openedStatus
            then pure ()
            else
              ioError
                (userError ("resolved executable changed while opening: " <> path))
          restore observeOpened
          digestContext <- restore (hashExecutableDescriptor SHA256.init descriptor)
          finalDescriptorStatus <- Posix.getFdStatus descriptor
          finalPathStatus <- Posix.getSymbolicLinkStatus path
          if stableExecutableStatus openedStatus finalDescriptorStatus
            && stableExecutableStatus finalDescriptorStatus finalPathStatus
            && not (Posix.isSymbolicLink finalPathStatus)
            then
              pure
                ( openedStatus,
                  "sha256:"
                    <> TextEncoding.decodeUtf8
                      (Base16.encode (SHA256.finalize digestContext))
                )
            else
              ioError
                (userError ("resolved executable changed while hashing: " <> path))
      )
      (closeFd descriptor)

hashExecutableDescriptor :: SHA256.Ctx -> Fd -> IO SHA256.Ctx
hashExecutableDescriptor digestContext descriptor = do
  readResult <-
    try @IOException
      (PosixByteString.fdRead descriptor executableDigestChunkBytes)
  chunk <-
    case readResult of
      Right bytes -> pure bytes
      Left failure
        | isEOFError failure -> pure ByteString.empty
        | otherwise -> ioError failure
  if ByteString.null chunk
    then pure digestContext
    else
      hashExecutableDescriptor
        (SHA256.update digestContext chunk)
        descriptor

executableDigestChunkBytes :: ByteCount
executableDigestChunkBytes = 64 * 1024

-- | Package-internal adversarial hook. The mutation is fixed to replacing the
-- configured file after its no-follow descriptor has opened, so tests can
-- prove that no capability is minted from a mixed pathname/file identity.
executableMutationDuringHashRejectedForTest ::
  FilePath ->
  FilePath ->
  IO Bool
executableMutationDuringHashRejectedForTest executablePath replacementPath = do
  listedStatus <- Posix.getSymbolicLinkStatus executablePath
  result <-
    try @IOException
      ( digestExecutableWithObserver
          executablePath
          listedStatus
          (Directory.renameFile replacementPath executablePath)
      )
  pure $
    case result of
      Left _ -> True
      Right _ -> False

parseAppleRuntimeVersionForTest ::
  AppleAdapterId ->
  ByteString.ByteString ->
  Either String AppleRuntimeVersion
parseAppleRuntimeVersionForTest (AppleAdapterId adapter) =
  parseAppleRuntimeVersion adapter

parseAppleRuntimeVersion ::
  Internal.AppleAdapterId ->
  ByteString.ByteString ->
  Either String AppleRuntimeVersion
parseAppleRuntimeVersion adapter rawOutput = do
  unlessEither
    ( not (ByteString.null rawOutput)
        && ByteString.length rawOutput <= 64 * 1024
        && not (ByteString.any (== 0) rawOutput)
    )
    "Apple runtime smoke output is empty, oversized, or contains NUL"
  output <-
    either
      (Left . ("Apple runtime smoke output is not UTF-8: " <>) . show)
      Right
      (TextEncoding.decodeUtf8' rawOutput)
  outputLines <- exactRuntimeOutputLines output
  version <-
    case adapter of
      Internal.LlamaCppCliAdapter ->
        parseLlamaRuntimeVersion outputLines
      Internal.WhisperCppCliAdapter ->
        parseWhisperRuntimeVersion outputLines
      Internal.CTranslate2Adapter ->
        parsePythonRuntimeVersion
          adapter
          ["ctranslate2", "faster-whisper"]
          rawOutput
      Internal.OnnxRuntimeAdapter ->
        parsePythonRuntimeVersion
          adapter
          ["onnxruntime"]
          rawOutput
      Internal.MlxAdapter ->
        parsePythonRuntimeVersion
          adapter
          ["mlx", "mlx-lm"]
          rawOutput
      Internal.CoreMlAdapter ->
        parsePythonRuntimeVersion
          adapter
          [ "apple-ml-stable-diffusion",
            "basic-pitch",
            "coremltools"
          ]
          rawOutput
      Internal.JvmAdapter ->
        parseAudiverisRuntimeVersion outputLines
  unlessEither
    (validNormalizedRuntimeVersion version)
    "Apple runtime smoke produced an invalid normalized version"
  pure (AppleRuntimeVersion version)

parseLlamaRuntimeVersion :: [Text] -> Either String Text
parseLlamaRuntimeVersion outputLines =
  case outputLines of
    [versionLine, buildLine] -> do
      payload <-
        maybe
          (Left "llama-cli smoke omitted its exact version line")
          Right
          (Text.stripPrefix "version: " versionLine)
      unlessEither
        ( maybe
            False
            validLlamaBuildProvenance
            (Text.stripPrefix "built with " buildLine)
        )
        "llama-cli smoke has an invalid build-provenance line"
      case Text.words payload of
        [build, parenthesizedHash] -> do
          commit <-
            maybe
              (Left "llama-cli smoke version has an invalid commit hash")
              Right
              ( Text.stripSuffix ")"
                  =<< Text.stripPrefix "(" parenthesizedHash
              )
          unlessEither
            ( validPositiveDecimal build
                && Text.length commit >= 8
                && Text.length commit <= 64
                && Text.all isAsciiLowerHexDigit commit
            )
            "llama-cli smoke version has an invalid build or commit"
          pure ("llama.cpp-b" <> build <> "-" <> commit)
        _ ->
          Left "llama-cli smoke version has an invalid token cardinality"
    _ ->
      Left "llama-cli smoke must emit exactly two lines"

parseWhisperRuntimeVersion :: [Text] -> Either String Text
parseWhisperRuntimeVersion outputLines =
  case outputLines of
    [versionLine] -> do
      version <-
        maybe
          (Left "whisper-cli smoke omitted its exact version line")
          Right
          (Text.stripPrefix "whisper.cpp version: " versionLine)
      unlessEither
        (validVersionAtom version)
        "whisper-cli smoke emitted an invalid version"
      pure version
    _ ->
      Left "whisper-cli smoke must emit exactly one line"

parsePythonRuntimeVersion ::
  Internal.AppleAdapterId ->
  [Text] ->
  ByteString.ByteString ->
  Either String Text
parsePythonRuntimeVersion adapter expectedKeys rawOutput = do
  value <-
    either
      (Left . ("Python Apple runtime smoke is not exact JSON: " <>))
      Right
      (Aeson.eitherDecodeStrict' rawOutput)
  fields <-
    AesonTypes.parseEither
      ( Aeson.withObject "ApplePythonRuntimeSmoke" $ \object -> do
          let topLevelKeys =
                List.sort
                  (map AesonKey.toText (AesonKeyMap.keys object))
          unless
            ( topLevelKeys
                == ["adapterId", "packages", "schemaVersion"]
            )
            (fail "Python Apple runtime smoke has an unexpected top-level field")
          schemaVersion <- object Aeson..: "schemaVersion"
          unless
            ((schemaVersion :: Int) == 1)
            (fail "Python Apple runtime smoke has an unsupported schema")
          adapterId <- object Aeson..: "adapterId"
          unless
            ( adapterId
                == Text.pack (Internal.appleAdapterSlug adapter)
            )
            (fail "Python Apple runtime smoke names another adapter")
          packages <- object Aeson..: "packages"
          Aeson.withObject
            "ApplePythonRuntimePackages"
            ( \packageObject -> do
                let packageKeys =
                      List.sort
                        (map AesonKey.toText (AesonKeyMap.keys packageObject))
                unless
                  (packageKeys == List.sort expectedKeys)
                  (fail "Python Apple runtime smoke has an unexpected package field set")
                mapM
                  ( \key -> do
                      version <-
                        packageObject
                          Aeson..: AesonKey.fromText key
                      unless
                        (validVersionAtom version)
                        (fail "Python Apple runtime smoke has an invalid package version")
                      pure (key, version)
                  )
                  expectedKeys
            )
            packages
      )
      value
  let canonicalOutput =
        TextEncoding.encodeUtf8
          ( "{\"adapterId\":\""
              <> Text.pack (Internal.appleAdapterSlug adapter)
              <> "\",\"packages\":{"
              <> Text.intercalate
                ","
                [ "\""
                    <> key
                    <> "\":\""
                    <> version
                    <> "\""
                | (key, version) <- fields
                ]
              <> "},\"schemaVersion\":1}\n"
          )
  unlessEither
    (rawOutput == canonicalOutput)
    "Python Apple runtime smoke is not canonical JSON"
  pure
    ( Text.intercalate
        ","
        [key <> "=" <> version | (key, version) <- fields]
    )

parseAudiverisRuntimeVersion :: [Text] -> Either String Text
parseAudiverisRuntimeVersion outputLines =
  case outputLines of
    [ heading,
      versionLine,
      commitLine,
      osLine,
      architectureLine,
      javaLine,
      ocrLine
      ] -> do
        unlessEither
          (heading == "Audiveris")
          "Audiveris smoke has an invalid heading"
        version <-
          exactRuntimeField "- Version:      " versionLine
        _commit <- exactRuntimeField "- Commit:       " commitLine
        _os <- exactRuntimeField "- OS:           " osLine
        _architecture <-
          exactRuntimeField "- Architecture: " architectureLine
        _java <- exactRuntimeField "- Java VM:      " javaLine
        _ocr <- exactRuntimeField "- OCR Engine:   " ocrLine
        unlessEither
          ( validVersionAtom version
              && version == Text.pack Recipe.audiverisVersion
          )
          "Audiveris installed version disagrees with its checksum-bound receipt"
        pure version
    _ ->
      Left "Audiveris smoke must emit exactly seven version fields"

exactRuntimeOutputLines :: Text -> Either String [Text]
exactRuntimeOutputLines output = do
  unlessEither
    ("\n" `Text.isSuffixOf` output)
    "Apple runtime smoke output must end in exactly one terminal newline"
  let body = Text.dropEnd 1 output
      linesValue = Text.splitOn "\n" body
  unlessEither
    ( not (Text.null body)
        && all
          ( \line ->
              not (Text.null line)
                && not (Text.any (== '\r') line)
          )
          linesValue
    )
    "Apple runtime smoke output contains an empty or carriage-return line"
  pure linesValue

exactRuntimeField :: Text -> Text -> Either String Text
exactRuntimeField prefix line = do
  value <-
    maybe
      (Left "Apple runtime smoke omitted an exact field")
      Right
      (Text.stripPrefix prefix line)
  unlessEither
    (validExactRuntimeField value)
    "Apple runtime smoke has an empty or noncanonical exact field"
  pure value

validExactRuntimeField :: Text -> Bool
validExactRuntimeField value =
  not (Text.null value)
    && value == Text.strip value
    && Text.all
      (\character -> character >= ' ' && character <= '~')
      value

validPositiveDecimal :: Text -> Bool
validPositiveDecimal value =
  case Text.uncons value of
    Just (first, remaining) ->
      first >= '1'
        && first <= '9'
        && Text.length value <= 20
        && Text.all
          (\character -> isAscii character && isDigit character)
          remaining
    Nothing -> False

validLlamaBuildProvenance :: Text -> Bool
validLlamaBuildProvenance value =
  maybe
    False
    validExactRuntimeField
    (Text.stripSuffix " for Darwin arm64" value)

validNormalizedRuntimeVersion :: Text -> Bool
validNormalizedRuntimeVersion version =
  not (Text.null version)
    && Text.length version <= 1024
    && Text.all
      ( \character ->
          isAsciiAlphaNumeric character
            || character `elem` ("._+@:/=,-" :: String)
      )
      version

validVersionAtom :: Text -> Bool
validVersionAtom atom =
  not (Text.null atom)
    && Text.length atom <= 256
    && Text.all
      ( \character ->
          isAsciiAlphaNumeric character
            || character `elem` ("._+@:-" :: String)
      )
      atom

isAsciiAlphaNumeric :: Char -> Bool
isAsciiAlphaNumeric character =
  isAsciiLower character
    || isAsciiUpper character
    || (isAscii character && isDigit character)

isAsciiLowerHexDigit :: Char -> Bool
isAsciiLowerHexDigit character =
  (isAscii character && isDigit character)
    || (isAsciiLower character && character <= 'f')

newtype AppleManifestBuilder
  = AppleManifestBuilder
      ( AppleRuntimeVersion ->
        Text ->
        Either String Artifact.EngineArtifactManifest
      )

mkAppleManifestBuilder ::
  ( AppleRuntimeVersion ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  AppleManifestBuilder
mkAppleManifestBuilder =
  AppleManifestBuilder

-- | Pure manifest construction supplied by the closed Linux materializer.
-- Target observation, generation-lock ownership, smoke execution, durable
-- publication, and activation remain inside this module.
newtype LinuxManifestBuilder
  = LinuxManifestBuilder
      ( NativeArtifactTargetEvidence ->
        Text ->
        Either String Artifact.EngineArtifactManifest
      )

mkLinuxManifestBuilder ::
  ( NativeArtifactTargetEvidence ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  LinuxManifestBuilder
mkLinuxManifestBuilder =
  LinuxManifestBuilder

data LinuxCompletionPhase
  = LinuxPayloadHashed
  | LinuxGenerationExclusivePrepared
  | LinuxGenerationSharedReaped
  | LinuxGenerationExclusiveRevalidated
  | LinuxPublished

data LinuxCompletionState s (phase :: LinuxCompletionPhase) where
  LinuxPayloadHashedCompletionState ::
    ArtifactIdentity.NativeArtifactIdentity ->
    NativeArtifactTarget ->
    LinuxNativeSmokePolicy ->
    FilePath ->
    FilePath ->
    Text ->
    Artifact.EngineArtifactManifest ->
    ArtifactGenerationLease ->
    LinuxCompletionState s 'LinuxPayloadHashed
  LinuxGenerationExclusivePreparedCompletionState ::
    ArtifactIdentity.NativeArtifactIdentity ->
    NativeArtifactTarget ->
    LinuxNativeSmokePolicy ->
    FilePath ->
    FilePath ->
    Text ->
    Artifact.EngineArtifactManifest ->
    NativeArtifactTargetEvidence ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    LinuxCompletionState s 'LinuxGenerationExclusivePrepared
  LinuxGenerationSharedReapedCompletionState ::
    ArtifactIdentity.NativeArtifactIdentity ->
    NativeArtifactTarget ->
    LinuxNativeSmokePolicy ->
    FilePath ->
    FilePath ->
    Text ->
    Artifact.EngineArtifactManifest ->
    NativeArtifactTargetEvidence ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    ByteString.ByteString ->
    ByteString.ByteString ->
    LinuxCompletionState s 'LinuxGenerationSharedReaped
  LinuxGenerationExclusiveRevalidatedCompletionState ::
    ArtifactIdentity.NativeArtifactIdentity ->
    LinuxNativeSmokePolicy ->
    FilePath ->
    FilePath ->
    Text ->
    Artifact.EngineArtifactManifest ->
    NativeArtifactTargetEvidence ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    ByteString.ByteString ->
    ByteString.ByteString ->
    LinuxCompletionState s 'LinuxGenerationExclusiveRevalidated
  LinuxPublishedCompletionState ::
    ArtifactIdentity.NativeArtifactIdentity ->
    LinuxNativeSmokePolicy ->
    FilePath ->
    FilePath ->
    Text ->
    Artifact.EngineArtifactManifest ->
    ArtifactGenerationLease ->
    LinuxCompletionState s 'LinuxPublished

type role LinuxCompletionState nominal nominal

completeLinuxCandidate ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ArtifactIdentity.NativeArtifactIdentity ->
  NativeArtifactTarget ->
  LinuxNativeSmokePolicy ->
  FilePath ->
  FilePath ->
  LinuxManifestBuilder ->
  ProvisioningSession s ()
completeLinuxCandidate
  (EngineWriter authority recovered authorizedRoot)
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  identity
  target
  smokePolicy
  installRoot
  candidateRoot
  (LinuxManifestBuilder buildManifest) =
    ProvisioningSession $ do
      authorizedInstallRoot <-
        authorizedWriterPath
          "Linux native install root"
          authorizedRoot
          installRoot
      authorizedCandidateRoot <-
        authorizedWriterPath
          "Linux native candidate root"
          authorizedRoot
          candidateRoot
      unless
        ( normalise authorizedInstallRoot == normalise installRoot
            && normalise authorizedCandidateRoot == normalise candidateRoot
        )
        (ioError (userError "Linux candidate roots must use their canonical writer paths"))
      hashed <-
        hashLinuxCompletionState
          authorizedRoot
          identity
          target
          smokePolicy
          authorizedInstallRoot
          authorizedCandidateRoot
          buildManifest
      prepared <-
        prepareLinuxCompletionGeneration
          authority
          recovered
          buildManifest
          hashed
      sharedReaped <-
        smokeLinuxCompletionState
          environment
          deadline
          prepared
      publication <-
        withTryArtifactGenerationMutationLock
          authority
          (linuxCompletionGenerationLease sharedReaped)
          ( \generationAuthority -> do
              revalidated <-
                revalidateLinuxCompletionState
                  generationAuthority
                  buildManifest
                  sharedReaped
              publishLinuxCompletionState
                generationAuthority
                revalidated
          )
      published <-
        maybe
          (ioError (userError "Linux artifact generation is in use before publication"))
          pure
          publication
      activateLinuxCompletionState
        authority
        recovered
        environment
        timeout
        published
      validateWriterRootIdentity
        "Linux native candidate completion"
        authorizedRoot

linuxCompletionGenerationLease ::
  LinuxCompletionState s 'LinuxGenerationSharedReaped ->
  ArtifactGenerationLease
linuxCompletionGenerationLease
  ( LinuxGenerationSharedReapedCompletionState
      _
      _
      _
      _
      _
      _
      _
      _
      lease
      _
      _
      _
    ) =
    lease

reconcileRetainedArtifactGenerationLeases ::
  Subprocess.AbandonedActivitiesRecovered ->
  MaterializationAuthority w ->
  ArtifactIdentity.NativeArtifactIdentity ->
  FilePath ->
  ArtifactGenerationLease ->
  IO ()
reconcileRetainedArtifactGenerationLeases
  recovered
  authority
  identity
  installRoot
  proposedLease = do
    recovered `seq` pure ()
    currentManifestExists <-
      Directory.doesFileExist
        (Artifact.engineArtifactManifestPath installRoot)
    if not currentManifestExists
      then
        reconcileObsoleteArtifactGenerationLeases
          authority
          [proposedLease]
      else do
        currentManifestResult <-
          try @IOException
            (Artifact.validateEngineArtifactRootAt installRoot installRoot)
        case currentManifestResult of
          -- A pre-generation predecessor cannot supply an exact current
          -- lease. Its replacement commit performs the complete bounded
          -- reconciliation; candidate validation remains fail closed.
          Left _ -> pure ()
          Right currentManifest -> do
            unless
              ( Artifact.manifestAdapterId currentManifest
                  == ArtifactIdentity.nativeArtifactAdapterId identity
              )
              (ioError (userError "current artifact adapter changed before sidecar reconciliation"))
            let (enginesRoot, _, _, _) =
                  artifactGenerationLeaseFields proposedLease
            currentLease <-
              either
                ( ioError
                    . userError
                    . ("derive current artifact generation lease: " <>)
                )
                pure
                ( artifactGenerationLease
                    enginesRoot
                    identity
                    (Artifact.manifestGenerationFingerprint currentManifest)
                    (Artifact.manifestDigest currentManifest)
                )
            reconcileObsoleteArtifactGenerationLeases
              authority
              ( if currentLease == proposedLease
                  then [proposedLease]
                  else [proposedLease, currentLease]
              )

hashLinuxCompletionState ::
  AuthorizedWriterRoot ->
  ArtifactIdentity.NativeArtifactIdentity ->
  NativeArtifactTarget ->
  LinuxNativeSmokePolicy ->
  FilePath ->
  FilePath ->
  ( NativeArtifactTargetEvidence ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  IO (LinuxCompletionState s 'LinuxPayloadHashed)
hashLinuxCompletionState
  authorizedRoot
  identity
  target
  smokePolicy
  installRoot
  candidateRoot
  buildManifest = do
    payloadDigest <- Artifact.digestEngineArtifactPayload candidateRoot
    -- This first observation only derives a proposed generation sidecar.
    -- Exact evidence is observed again while that sidecar is exclusively held
    -- before any helper can start.
    proposedEvidence <-
      ArtifactInternal.observeNativeArtifactTargetEvidence
        installRoot
        target
    proposedManifest <-
      buildValidatedLinuxCompletionManifest
        identity
        target
        installRoot
        proposedEvidence
        payloadDigest
        buildManifest
    lease <-
      either
        (ioError . userError . ("derive Linux artifact generation lease: " <>))
        pure
        ( artifactGenerationLease
            (authorizedWriterCanonicalRoot authorizedRoot)
            identity
            (Artifact.manifestGenerationFingerprint proposedManifest)
            payloadDigest
        )
    pure
      ( LinuxPayloadHashedCompletionState
          identity
          target
          smokePolicy
          installRoot
          candidateRoot
          payloadDigest
          proposedManifest
          lease
      )

prepareLinuxCompletionGeneration ::
  MaterializationAuthority w ->
  Subprocess.AbandonedActivitiesRecovered ->
  ( NativeArtifactTargetEvidence ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  LinuxCompletionState s 'LinuxPayloadHashed ->
  IO (LinuxCompletionState s 'LinuxGenerationExclusivePrepared)
prepareLinuxCompletionGeneration
  authority
  recovered
  buildManifest
  ( LinuxPayloadHashedCompletionState
      identity
      target
      smokePolicy
      installRoot
      candidateRoot
      payloadDigest
      expectedManifest
      lease
    ) = do
    reconcileRetainedArtifactGenerationLeases
      recovered
      authority
      identity
      installRoot
      lease
    prepared <-
      withTryArtifactGenerationMutationLock
        authority
        lease
        ( \_generationAuthority -> do
            exactTargetEvidence <-
              revalidateLinuxCompletionCandidate
                identity
                target
                installRoot
                candidateRoot
                payloadDigest
                expectedManifest
                buildManifest
            mutationRootResult <-
              Subprocess.observeProvisioningMutationRoot candidateRoot
            mutationRoot <-
              either
                ( ioError
                    . userError
                    . ("observe retained Linux candidate root: " <>)
                    . renderProvisioningMutationOutcome
                )
                pure
                mutationRootResult
            pure
              ( LinuxGenerationExclusivePreparedCompletionState
                  identity
                  target
                  smokePolicy
                  installRoot
                  candidateRoot
                  payloadDigest
                  expectedManifest
                  exactTargetEvidence
                  lease
                  mutationRoot
              )
        )
    maybe
      (ioError (userError "Linux artifact generation is in use before smoke"))
      pure
      prepared

smokeLinuxCompletionState ::
  Subprocess.SubprocessEnv ->
  ProvisioningDeadline ->
  LinuxCompletionState s 'LinuxGenerationExclusivePrepared ->
  IO (LinuxCompletionState s 'LinuxGenerationSharedReaped)
smokeLinuxCompletionState
  environment
  deadline
  ( LinuxGenerationExclusivePreparedCompletionState
      identity
      target
      smokePolicy
      installRoot
      candidateRoot
      payloadDigest
      expectedManifest
      expectedTargetEvidence
      lease
      mutationRoot
    ) = do
    commandOutcome <-
      Subprocess.runClosedLinuxNativeArtifactSmoke
        identity
        lease
        mutationRoot
        expectedTargetEvidence
        (internalLinuxNativeSmokePolicy smokePolicy)
        environment
        (Subprocess.Timeout (provisioningDeadlineMicros deadline))
    (standardOutput, standardError) <-
      case commandOutcome of
        Right
          ( Subprocess.NativeArtifactCommandExited
              ExitSuccess
              output
              errors
            )
            | not (ByteString.null output) ->
                pure (output, errors)
        _ ->
          ioError
            ( userError
                ( "Linux engine artifact smoke failed: "
                    <> show commandOutcome
                )
            )
    pure
      ( LinuxGenerationSharedReapedCompletionState
          identity
          target
          smokePolicy
          installRoot
          candidateRoot
          payloadDigest
          expectedManifest
          expectedTargetEvidence
          lease
          mutationRoot
          standardOutput
          standardError
      )

revalidateLinuxCompletionState ::
  ArtifactGenerationMutationAuthority w g ->
  ( NativeArtifactTargetEvidence ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  LinuxCompletionState s 'LinuxGenerationSharedReaped ->
  IO (LinuxCompletionState s 'LinuxGenerationExclusiveRevalidated)
revalidateLinuxCompletionState
  _generationAuthority
  buildManifest
  ( LinuxGenerationSharedReapedCompletionState
      identity
      target
      smokePolicy
      installRoot
      candidateRoot
      payloadDigest
      expectedManifest
      _expectedTargetEvidence
      lease
      mutationRoot
      standardOutput
      standardError
    ) = do
    exactTargetEvidence <-
      revalidateLinuxCompletionCandidate
        identity
        target
        installRoot
        candidateRoot
        payloadDigest
        expectedManifest
        buildManifest
    pure
      ( LinuxGenerationExclusiveRevalidatedCompletionState
          identity
          smokePolicy
          installRoot
          candidateRoot
          payloadDigest
          expectedManifest
          exactTargetEvidence
          lease
          mutationRoot
          standardOutput
          standardError
      )

publishLinuxCompletionState ::
  ArtifactGenerationMutationAuthority w g ->
  LinuxCompletionState s 'LinuxGenerationExclusiveRevalidated ->
  IO (LinuxCompletionState s 'LinuxPublished)
publishLinuxCompletionState
  _generationAuthority
  ( LinuxGenerationExclusiveRevalidatedCompletionState
      identity
      smokePolicy
      installRoot
      candidateRoot
      payloadDigest
      expectedManifest
      _expectedTargetEvidence
      lease
      _mutationRoot
      _standardOutput
      _standardError
    ) = do
    publishCandidateManifestFile candidateRoot expectedManifest
    validated <-
      Artifact.validateEngineArtifactRootAt installRoot candidateRoot
    unless
      (validated == expectedManifest)
      (ioError (userError "published Linux candidate manifest did not validate exactly"))
    pure
      ( LinuxPublishedCompletionState
          identity
          smokePolicy
          installRoot
          candidateRoot
          payloadDigest
          expectedManifest
          lease
      )

activateLinuxCompletionState ::
  MaterializationAuthority w ->
  Subprocess.AbandonedActivitiesRecovered ->
  Subprocess.SubprocessEnv ->
  Internal.PositiveProvisioningTimeout ->
  LinuxCompletionState s 'LinuxPublished ->
  IO ()
activateLinuxCompletionState
  authority
  recovered
  environment
  timeout
  ( LinuxPublishedCompletionState
      identity
      smokePolicy
      installRoot
      candidateRoot
      payloadDigest
      _manifest
      lease
    ) = do
    result <-
      ArtifactActivation.activateLinuxEngineArtifactWithInstalledSmoke
        authority
        recovered
        lease
        environment
        timeout
        identity
        (internalLinuxNativeSmokePolicy smokePolicy)
        installRoot
        candidateRoot
        payloadDigest
    case result of
      Right
        ( Subprocess.NativeArtifactCommandExited
            ExitSuccess
            standardOutput
            _
          )
          | not (ByteString.null standardOutput) ->
              pure ()
      _ ->
        ioError
          ( userError
              ( "installed Linux artifact smoke failed: "
                  <> show result
              )
          )

revalidateLinuxCompletionCandidate ::
  ArtifactIdentity.NativeArtifactIdentity ->
  NativeArtifactTarget ->
  FilePath ->
  FilePath ->
  Text ->
  Artifact.EngineArtifactManifest ->
  ( NativeArtifactTargetEvidence ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  IO NativeArtifactTargetEvidence
revalidateLinuxCompletionCandidate
  identity
  target
  installRoot
  candidateRoot
  payloadDigest
  expectedManifest
  buildManifest = do
    observedDigest <- Artifact.digestEngineArtifactPayload candidateRoot
    unless
      (observedDigest == payloadDigest)
      (ioError (userError "Linux candidate payload changed under its generation lease"))
    observedEvidence <-
      ArtifactInternal.observeNativeArtifactTargetEvidence
        installRoot
        target
    observedManifest <-
      buildValidatedLinuxCompletionManifest
        identity
        target
        installRoot
        observedEvidence
        observedDigest
        buildManifest
    unless
      (observedManifest == expectedManifest)
      (ioError (userError "Linux target evidence changed under its generation lease"))
    pure observedEvidence

buildValidatedLinuxCompletionManifest ::
  ArtifactIdentity.NativeArtifactIdentity ->
  NativeArtifactTarget ->
  FilePath ->
  NativeArtifactTargetEvidence ->
  Text ->
  ( NativeArtifactTargetEvidence ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  IO Artifact.EngineArtifactManifest
buildValidatedLinuxCompletionManifest
  identity
  target
  installRoot
  targetEvidence
  payloadDigest
  buildManifest = do
    manifest <-
      either
        (ioError . userError . ("build pure Linux artifact manifest: " <>))
        pure
        (buildManifest targetEvidence payloadDigest)
    either
      (ioError . userError . ("validate pure Linux artifact manifest: " <>))
      pure
      ( validateLinuxCompletionManifest
          identity
          target
          installRoot
          targetEvidence
          payloadDigest
          manifest
      )
    pure manifest

validateLinuxCompletionManifest ::
  ArtifactIdentity.NativeArtifactIdentity ->
  NativeArtifactTarget ->
  FilePath ->
  NativeArtifactTargetEvidence ->
  Text ->
  Artifact.EngineArtifactManifest ->
  Either String ()
validateLinuxCompletionManifest
  identity
  target
  installRoot
  targetEvidence
  payloadDigest
  manifest = do
    closedTarget <-
      nativeArtifactTarget
        identity
        "linux-native"
        linuxCompletionArchitecture
    let targetFingerprint =
          nativeArtifactTargetFingerprint target
        closedTargetFingerprint =
          nativeArtifactTargetFingerprint closedTarget
    unless
      (targetFingerprint == closedTargetFingerprint)
      (Left "Linux completion target disagrees with the closed identity and runtime lane")
    expectedRecipeFingerprint <-
      Artifact.currentArtifactRecipeFingerprint
        identity
        Artifact.linuxArtifactRuntimeExpectation
    expectedGenerationFingerprint <-
      Artifact.engineArtifactGenerationFingerprint
        "linux-native"
        payloadDigest
        expectedRecipeFingerprint
        targetFingerprint
        (Just targetEvidence)
    unless
      ( Artifact.manifestAdapterId manifest
          == ArtifactIdentity.nativeArtifactAdapterId identity
          && Artifact.manifestSubstrate manifest == "linux-native"
          && Artifact.manifestArchitecture manifest
            == linuxCompletionArchitecture
          && Artifact.manifestRecipeFingerprint manifest
            == expectedRecipeFingerprint
          && Artifact.manifestDigest manifest == payloadDigest
          && Artifact.manifestGenerationFingerprint manifest
            == expectedGenerationFingerprint
          && Artifact.manifestLocalInstallRoot manifest == installRoot
          && Artifact.manifestTargetContractFingerprint manifest
            == targetFingerprint
          && Artifact.manifestImageTargetEvidence manifest
            == Just targetEvidence
      )
      (Left "manifest fields disagree with the closed Linux completion authority")

internalLinuxNativeSmokePolicy ::
  LinuxNativeSmokePolicy ->
  Internal.LinuxNativeSmokePolicy
internalLinuxNativeSmokePolicy policy =
  case policy of
    RequireImagePayload -> Internal.RequireImagePayload
    AllowFixturePayloadAbsence ->
      Internal.AllowFixturePayloadAbsence

linuxCompletionArchitecture :: Text
linuxCompletionArchitecture =
  case SystemInfo.arch of
    "x86_64" -> "amd64"
    "aarch64" -> "arm64"
    other -> Text.pack other

data AppleCompletionPhase
  = PayloadHashed
  | GenerationExclusivePrepared
  | GenerationSharedReaped
  | GenerationExclusiveRevalidated
  | Published

data AppleCompletionState s (phase :: AppleCompletionPhase) where
  PayloadHashedCompletionState ::
    Internal.AppleAdapterId ->
    ArtifactIdentity.NativeArtifactIdentity ->
    FilePath ->
    FilePath ->
    Text ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    AppleCompletionState s 'PayloadHashed
  GenerationExclusivePreparedCompletionState ::
    Internal.AppleAdapterId ->
    ArtifactIdentity.NativeArtifactIdentity ->
    FilePath ->
    FilePath ->
    Text ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    AppleCompletionState s 'GenerationExclusivePrepared
  GenerationSharedReapedCompletionState ::
    Internal.AppleAdapterId ->
    ArtifactIdentity.NativeArtifactIdentity ->
    FilePath ->
    FilePath ->
    Text ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    AppleRuntimeVersion ->
    ByteString.ByteString ->
    ByteString.ByteString ->
    AppleCompletionState s 'GenerationSharedReaped
  GenerationExclusiveRevalidatedCompletionState ::
    Internal.AppleAdapterId ->
    ArtifactIdentity.NativeArtifactIdentity ->
    FilePath ->
    FilePath ->
    Text ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    AppleRuntimeVersion ->
    ByteString.ByteString ->
    ByteString.ByteString ->
    NativeArtifactTargetEvidence ->
    AppleCompletionState s 'GenerationExclusiveRevalidated
  PublishedCompletionState ::
    Internal.AppleAdapterId ->
    FilePath ->
    FilePath ->
    Text ->
    ArtifactGenerationLease ->
    Subprocess.ProvisioningMutationRoot ->
    AppleCompletionState s 'Published

type role AppleCompletionState nominal nominal

completeAppleCandidate ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  AppleAdapterId ->
  FilePath ->
  FilePath ->
  AppleManifestBuilder ->
  ProvisioningSession s ()
completeAppleCandidate
  (EngineWriter authority recovered authorizedRoot)
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  (AppleAdapterId adapter)
  installRoot
  candidateRoot
  (AppleManifestBuilder buildManifest) =
    ProvisioningSession $ do
      authorizedInstallRoot <-
        authorizedWriterPath
          "Apple candidate install root"
          authorizedRoot
          installRoot
      authorizedCandidateRoot <-
        authorizedWriterPath
          "Apple candidate transaction root"
          authorizedRoot
          candidateRoot
      unless
        ( normalise authorizedInstallRoot == normalise installRoot
            && normalise authorizedCandidateRoot == normalise candidateRoot
        )
        (ioError (userError "Apple candidate roots must use their canonical writer paths"))
      validation <-
        validateHydratedCandidate
          adapter
          authorizedInstallRoot
          authorizedCandidateRoot
      either
        (ioError . userError . ("refine hydrated Apple candidate: " <>))
        pure
        validation
      hashed <-
        hashAppleCompletionState
          authorizedRoot
          adapter
          authorizedInstallRoot
          authorizedCandidateRoot
      prepared <-
        prepareAppleCompletionGeneration
          authority
          recovered
          hashed
      sharedReaped <-
        smokeAppleCompletionState
          environment
          deadline
          prepared
      publication <-
        withTryArtifactGenerationMutationLock
          authority
          (appleCompletionGenerationLease sharedReaped)
          ( \generationAuthority -> do
              revalidated <-
                revalidateAppleCompletionState
                  generationAuthority
                  sharedReaped
              publishAppleCompletionState
                generationAuthority
                buildManifest
                revalidated
          )
      (published, manifest) <-
        maybe
          (ioError (userError "Apple artifact generation is in use"))
          pure
          publication
      activateAppleCompletionState
        authority
        recovered
        environment
        timeout
        published
        manifest
      validateWriterRootIdentity
        "Apple candidate completion"
        authorizedRoot

appleCompletionGenerationLease ::
  AppleCompletionState s 'GenerationSharedReaped ->
  ArtifactGenerationLease
appleCompletionGenerationLease
  ( GenerationSharedReapedCompletionState
      _
      _
      _
      _
      _
      lease
      _
      _
      _
      _
    ) =
    lease

hashAppleCompletionState ::
  AuthorizedWriterRoot ->
  Internal.AppleAdapterId ->
  FilePath ->
  FilePath ->
  IO (AppleCompletionState s 'PayloadHashed)
hashAppleCompletionState
  authorizedRoot
  adapter
  installRoot
  candidateRoot = do
    digest <- Artifact.digestEngineArtifactPayload candidateRoot
    identity <-
      either
        (ioError . userError)
        pure
        (Internal.nativeArtifactIdentity adapter)
    lease <-
      either
        (ioError . userError . ("derive Apple artifact generation lease: " <>))
        pure
        ( artifactGenerationLease
            (authorizedWriterCanonicalRoot authorizedRoot)
            identity
            digest
            digest
        )
    mutationRootResult <-
      Subprocess.observeProvisioningMutationRoot candidateRoot
    mutationRoot <-
      case mutationRootResult of
        Left failure ->
          ioError
            ( userError
                ( "observe retained Apple candidate root: "
                    <> renderProvisioningMutationOutcome failure
                )
            )
        Right observed -> pure observed
    pure
      ( PayloadHashedCompletionState
          adapter
          identity
          installRoot
          candidateRoot
          digest
          lease
          mutationRoot
      )

prepareAppleCompletionGeneration ::
  MaterializationAuthority w ->
  Subprocess.AbandonedActivitiesRecovered ->
  AppleCompletionState s 'PayloadHashed ->
  IO (AppleCompletionState s 'GenerationExclusivePrepared)
prepareAppleCompletionGeneration
  authority
  recovered
  ( PayloadHashedCompletionState
      adapter
      identity
      installRoot
      candidateRoot
      digest
      lease
      mutationRoot
    ) = do
    reconcileRetainedArtifactGenerationLeases
      recovered
      authority
      identity
      installRoot
      lease
    prepared <-
      withTryArtifactGenerationMutationLock
        authority
        lease
        ( \_generationAuthority -> do
            observedDigest <-
              Artifact.digestEngineArtifactPayload candidateRoot
            unless
              (observedDigest == digest)
              (ioError (userError "candidate changed while generation lease was minted"))
            target <-
              either
                (ioError . userError . ("derive closed Apple artifact target: " <>))
                pure
                (nativeArtifactTarget identity "apple-silicon" "arm64")
            _ <-
              ArtifactInternal.observeNativeArtifactTargetEvidence
                candidateRoot
                target
            pure
              ( GenerationExclusivePreparedCompletionState
                  adapter
                  identity
                  installRoot
                  candidateRoot
                  digest
                  lease
                  mutationRoot
              )
        )
    maybe
      (ioError (userError "Apple artifact generation is in use before smoke"))
      pure
      prepared

smokeAppleCompletionState ::
  Subprocess.SubprocessEnv ->
  ProvisioningDeadline ->
  AppleCompletionState s 'GenerationExclusivePrepared ->
  IO (AppleCompletionState s 'GenerationSharedReaped)
smokeAppleCompletionState
  environment
  deadline
  ( GenerationExclusivePreparedCompletionState
      adapter
      identity
      installRoot
      candidateRoot
      digest
      lease
      mutationRoot
    ) = do
    commandOutcome <-
      Subprocess.runClosedInstalledRunnerSmoke
        adapter
        lease
        mutationRoot
        environment
        (Subprocess.Timeout (provisioningDeadlineMicros deadline))
    (standardOutput, standardError) <-
      case commandOutcome of
        Right
          ( Subprocess.NativeArtifactCommandExited
              ExitSuccess
              output
              errors
            ) ->
            pure (output, errors)
        _ ->
          ioError
            ( userError
                ( "Apple engine artifact smoke failed: "
                    <> show commandOutcome
                )
            )
    runtimeVersion <-
      either
        (ioError . userError . ("parse exact Apple runtime version: " <>))
        pure
        ( parseAppleRuntimeVersion
            adapter
            standardOutput
        )
    pure
      ( GenerationSharedReapedCompletionState
          adapter
          identity
          installRoot
          candidateRoot
          digest
          lease
          mutationRoot
          runtimeVersion
          standardOutput
          standardError
      )

revalidateAppleCompletionState ::
  ArtifactGenerationMutationAuthority w g ->
  AppleCompletionState s 'GenerationSharedReaped ->
  IO (AppleCompletionState s 'GenerationExclusiveRevalidated)
revalidateAppleCompletionState
  _generationAuthority
  ( GenerationSharedReapedCompletionState
      adapter
      identity
      installRoot
      candidateRoot
      digest
      lease
      mutationRoot
      runtimeVersion
      standardOutput
      standardError
    ) = do
    observedDigest <-
      Artifact.digestEngineArtifactPayload candidateRoot
    unless
      (observedDigest == digest)
      (ioError (userError "smoked candidate changed before exclusive revalidation"))
    target <-
      either
        (ioError . userError . ("derive closed Apple artifact target: " <>))
        pure
        (nativeArtifactTarget identity "apple-silicon" "arm64")
    targetEvidence <-
      ArtifactInternal.observeNativeArtifactTargetEvidence
        candidateRoot
        target
    pure
      ( GenerationExclusiveRevalidatedCompletionState
          adapter
          identity
          installRoot
          candidateRoot
          digest
          lease
          mutationRoot
          runtimeVersion
          standardOutput
          standardError
          targetEvidence
      )

publishAppleCompletionState ::
  ArtifactGenerationMutationAuthority w g ->
  ( AppleRuntimeVersion ->
    Text ->
    Either String Artifact.EngineArtifactManifest
  ) ->
  AppleCompletionState s 'GenerationExclusiveRevalidated ->
  IO
    ( AppleCompletionState s 'Published,
      Artifact.EngineArtifactManifest
    )
publishAppleCompletionState
  _generationAuthority
  buildManifest
  ( GenerationExclusiveRevalidatedCompletionState
      adapter
      _identity
      installRoot
      candidateRoot
      digest
      lease
      mutationRoot
      runtimeVersion
      _standardOutput
      _standardError
      _targetEvidence
    ) = do
    manifest <-
      either
        (ioError . userError . ("build pure Apple artifact manifest: " <>))
        pure
        (buildManifest runtimeVersion digest)
    let expectedAdapter =
          Text.pack (Internal.appleAdapterSlug adapter)
    unless
      ( Artifact.manifestAdapterId manifest == expectedAdapter
          && Artifact.manifestLocalInstallRoot manifest == installRoot
          && Artifact.manifestDigest manifest == digest
      )
      (ioError (userError "candidate manifest disagrees with its smoked authority"))
    observedDigest <-
      Artifact.digestEngineArtifactPayload candidateRoot
    unless
      (observedDigest == digest)
      (ioError (userError "smoked candidate changed before manifest publication"))
    publishCandidateManifestFile candidateRoot manifest
    validated <-
      Artifact.validateEngineArtifactRootAt installRoot candidateRoot
    unless
      (validated == manifest)
      (ioError (userError "published candidate manifest did not validate exactly"))
    pure
      ( PublishedCompletionState
          adapter
          installRoot
          candidateRoot
          digest
          lease
          mutationRoot,
        manifest
      )

activateAppleCompletionState ::
  MaterializationAuthority w ->
  Subprocess.AbandonedActivitiesRecovered ->
  Subprocess.SubprocessEnv ->
  Internal.PositiveProvisioningTimeout ->
  AppleCompletionState s 'Published ->
  Artifact.EngineArtifactManifest ->
  IO ()
activateAppleCompletionState
  authority
  recovered
  environment
  timeout
  ( PublishedCompletionState
      adapter
      installRoot
      candidateRoot
      digest
      lease
      _mutationRoot
    )
  _manifest = do
    result <-
      ArtifactActivation.activateAppleEngineArtifactWithInstalledSmoke
        authority
        recovered
        lease
        environment
        timeout
        adapter
        installRoot
        candidateRoot
        digest
    case result of
      Right
        ( Subprocess.NativeArtifactCommandExited
            ExitSuccess
            standardOutput
            _
          )
          | not (ByteString.null standardOutput) ->
              pure ()
      _ ->
        ioError
          ( userError
              ( "installed Apple artifact smoke failed: "
                  <> show result
              )
          )

publishCandidateManifestFile ::
  FilePath ->
  Artifact.EngineArtifactManifest ->
  IO ()
publishCandidateManifestFile candidateRoot manifest =
  mask $ \restore -> do
    let manifestPath = Artifact.engineArtifactManifestPath candidateRoot
        contents =
          LazyByteString.toStrict
            (Artifact.renderEngineArtifactManifest manifest)
    unless
      (ByteString.length contents <= 1024 * 1024)
      (ioError (userError "candidate manifest exceeds its fixed byte bound"))
    descriptor <-
      openFd
        manifestPath
        WriteOnly
        defaultFileFlags
          { exclusive = True,
            nofollow = True,
            creat =
              Just
                (Posix.ownerReadMode .|. Posix.ownerWriteMode),
            cloexec = True
          }
    onExceptionPreservingPrimary
      ( finallyPreservingPrimary
          ( restore $ do
              writeProvisioningDescriptor descriptor contents
              fileSynchronise descriptor
          )
          (closeFd descriptor)
      )
      (Directory.removeFile manifestPath)
    synchroniseProvisioningDirectory candidateRoot

validateHydratedCandidate ::
  Internal.AppleAdapterId ->
  FilePath ->
  FilePath ->
  IO (Either String ())
validateHydratedCandidate adapter installRoot candidateRoot
  | not (isAbsolute installRoot) =
      pure (Left ("candidate install root must be absolute: " <> installRoot))
  | normalise candidateRoot
      /= normalise (Artifact.engineArtifactTempRoot installRoot) =
      pure
        ( Left
            ( "candidate root must be the exact transaction sibling: "
                <> candidateRoot
            )
        )
  | otherwise = do
      candidateOkay <- regularDirectory candidateRoot
      targetOkay <-
        regularExecutable
          ( candidateRoot
              </> Internal.installedSmokeExecutableRelativePath adapter
          )
      payloadOkay <-
        case adapter of
          Internal.LlamaCppCliAdapter ->
            hostBinaryPayloadOkay "llama-cli"
          Internal.WhisperCppCliAdapter ->
            hostBinaryPayloadOkay "whisper-cli"
          Internal.CTranslate2Adapter -> pythonPayloadOkay
          Internal.OnnxRuntimeAdapter -> pythonPayloadOkay
          Internal.MlxAdapter -> pythonPayloadOkay
          Internal.CoreMlAdapter -> pythonPayloadOkay
          Internal.JvmAdapter ->
            regularExecutable
              ( candidateRoot
                  </> "Audiveris.app"
                  </> "Contents"
                  </> "MacOS"
                  </> "Audiveris"
              )
      pure
        ( if candidateOkay && targetOkay && payloadOkay
            then Right ()
            else
              Left
                ( "candidate is not fully hydrated for "
                    <> Internal.appleAdapterSlug adapter
                    <> ": "
                    <> candidateRoot
                )
        )
  where
    pythonPayloadOkay = do
      pythonOkay <-
        regularExecutable
          (candidateRoot </> Internal.fixedVenvPythonRelativePath)
      runnerLibraryOkay <-
        regularFile
          (candidateRoot </> "lib" </> "apple_native_runner.py")
      homeOkay <-
        regularDirectory (candidateRoot </> "python-home")
      frameworksOkay <-
        regularDirectory (candidateRoot </> "python-frameworks")
      pure
        ( pythonOkay
            && runnerLibraryOkay
            && homeOkay
            && frameworksOkay
        )
    hostBinaryPayloadOkay binaryName = do
      binaryOkay <-
        regularExecutable
          (candidateRoot </> "native" </> "bin" </> binaryName)
      libraryRootOkay <-
        regularDirectory (candidateRoot </> "native" </> "lib")
      libexecRootOkay <-
        regularDirectory (candidateRoot </> "native" </> "libexec")
      frameworkRootOkay <-
        regularDirectory (candidateRoot </> "native" </> "frameworks")
      pure
        ( binaryOkay
            && libraryRootOkay
            && libexecRootOkay
            && frameworkRootOkay
        )
    regularDirectory path = do
      statusResult <-
        tryPathStatus path
      pure
        ( case statusResult of
            Just status ->
              Posix.isDirectory status && not (Posix.isSymbolicLink status)
            Nothing -> False
        )
    regularExecutable path = do
      statusResult <- tryPathStatus path
      case statusResult of
        Just status
          | Posix.isRegularFile status
              && not (Posix.isSymbolicLink status) ->
              Directory.executable <$> Directory.getPermissions path
        _ -> pure False
    regularFile path = do
      statusResult <- tryPathStatus path
      pure
        ( case statusResult of
            Just status ->
              Posix.isRegularFile status
                && not (Posix.isSymbolicLink status)
            Nothing -> False
        )
    tryPathStatus path = do
      present <- Directory.doesPathExist path
      if present
        then Just <$> Posix.getSymbolicLinkStatus path
        else pure Nothing

failProvisioningSession :: String -> ProvisioningSession s result
failProvisioningSession =
  ProvisioningSession . ioError . userError

-- | Package-internal deterministic cancellation seam. It can only signal and
-- await already-created synchronization cells; it grants no raw IO, process,
-- filesystem, or command authority to the session.
pauseProvisioningSessionForTest ::
  MVar () ->
  MVar () ->
  ProvisioningSession s ()
pauseProvisioningSessionForTest entered resume =
  ProvisioningSession $ do
    putMVar entered ()
    takeMVar resume

-- | Run one closed acquisition interruptibly, then mask the evidence-refining
-- continuation. This closes the asynchronous gap between a successful kernel
-- operation and durable publication without exposing an arbitrary IO lift.
commitAfterInterruptibleProvisioning ::
  ProvisioningSession s acquired ->
  (acquired -> ProvisioningSession s committed) ->
  ProvisioningSession s committed
commitAfterInterruptibleProvisioning
  (ProvisioningSession acquire)
  refine =
    ProvisioningSession $
      mask $ \restore -> do
        acquired <- restore acquire
        case refine acquired of
          ProvisioningSession commit -> commit

provisioningDoesDirectoryExist :: FilePath -> ProvisioningSession s Bool
provisioningDoesDirectoryExist =
  ProvisioningSession . Directory.doesDirectoryExist

provisioningDoesPathExist :: FilePath -> ProvisioningSession s Bool
provisioningDoesPathExist =
  ProvisioningSession . Directory.doesPathExist

provisioningDoesFileExist :: FilePath -> ProvisioningSession s Bool
provisioningDoesFileExist =
  ProvisioningSession . Directory.doesFileExist

provisioningGetModificationTime :: FilePath -> ProvisioningSession s UTCTime
provisioningGetModificationTime =
  ProvisioningSession . Directory.getModificationTime

provisioningPoetryProjectReady ::
  ProjectWriter p s q ->
  ProvisioningSession s Bool
provisioningPoetryProjectReady (ProjectWriter _ projectRoot) =
  ProvisioningSession $ do
    validateWriterRootIdentity "Poetry project readiness" projectRoot
    status <-
      Posix.getFdStatus
        (authorizedWriterRootDescriptor projectRoot)
    pure (Posix.isDirectory status)

provisioningPoetryBootstrapExecutable ::
  PoetryBootstrapWriter b s q ->
  ProvisioningSession s (Maybe FilePath)
provisioningPoetryBootstrapExecutable
  (PoetryBootstrapWriter _ homeRoot poetryHome) =
    ProvisioningSession $ do
      let executable =
            poetryHome </> "venv" </> "bin" </> "poetry"
      observed <-
        observeAuthorizedPathStatus
          "Poetry bootstrap executable"
          homeRoot
          executable
      pure
        ( case observed of
            Just status
              | Posix.isRegularFile status
                  && Posix.fileMode status
                    .&. ( Posix.ownerExecuteMode
                            .|. Posix.groupExecuteMode
                            .|. Posix.otherExecuteMode
                        )
                    /= 0 ->
                  Just executable
            _ -> Nothing
        )

provisioningGeneratedBindingsRequired ::
  GeneratedBindingsWriter g s q ->
  ProvisioningSession s Bool
provisioningGeneratedBindingsRequired
  (GeneratedBindingsWriter _ repositoryRoot outputRoot) =
    ProvisioningSession $ do
      let repository = authorizedWriterCanonicalRoot repositoryRoot
          sourcePaths =
            [ repository
                </> "proto"
                </> "infernix"
                </> "manifest"
                </> "runtime_manifest.proto",
              repository
                </> "proto"
                </> "infernix"
                </> "runtime"
                </> "inference.proto"
            ]
          generatedPaths =
            [ outputRoot
                </> "infernix"
                </> "manifest"
                </> "runtime_manifest_pb2.py",
              outputRoot
                </> "infernix"
                </> "runtime"
                </> "inference_pb2.py"
            ]
      sourceStatuses <-
        mapM
          (observeAuthorizedPathStatus "protobuf source" repositoryRoot)
          sourcePaths
      unless
        (all (maybe False Posix.isRegularFile) sourceStatuses)
        (ioError (userError "fixed protobuf source set is incomplete"))
      generatedStatuses <-
        mapM
          (observeAuthorizedPathStatus "generated protobuf binding" repositoryRoot)
          generatedPaths
      case sequence generatedStatuses of
        Nothing -> pure True
        Just installed ->
          pure
            ( minimum (map Posix.modificationTimeHiRes installed)
                < maximum
                  [ Posix.modificationTimeHiRes status
                  | Just status <- sourceStatuses
                  ]
            )

provisioningAppleSetupReady ::
  EngineWriter w s q ->
  ApplePoetrySetupId ->
  FilePath ->
  ProvisioningSession s Bool
provisioningAppleSetupReady
  (EngineWriter _ _ engineRoot)
  (ApplePoetrySetupId setup)
  installRoot =
    ProvisioningSession $ do
      let manifestPath = installRoot </> "bootstrap.json"
          expected = appleSetupManifestBytes setup
      observed <-
        try @IOException
          ( readAuthorizedRegularFile
              "Apple setup bootstrap manifest"
              engineRoot
              manifestPath
              (fromIntegral (ByteString.length expected))
          )
      pure
        ( case observed of
            Right contents -> contents == expected
            Left failure
              | isDoesNotExistError failure -> False
              | otherwise -> False
        )

-- | Publish the complete Python-adapter bootstrap evidence without spawning
-- a nested Poetry child. The adapter id is closed, the payload is canonical,
-- and the fixed sibling staging file is written through the retained parent
-- descriptor before the bounded mutation kernel atomically renames it.
provisioningPublishAppleSetupManifest ::
  EngineWriter w s q ->
  ApplePoetrySetupId ->
  FilePath ->
  ProvisioningSession s ()
provisioningPublishAppleSetupManifest =
  provisioningPublishAppleSetupManifestInternal Nothing

provisioningPublishAppleSetupManifestWithPauseForTest ::
  EngineWriter w s q ->
  ApplePoetrySetupId ->
  FilePath ->
  MVar () ->
  MVar () ->
  ProvisioningSession s ()
provisioningPublishAppleSetupManifestWithPauseForTest
  writer
  setup
  installRoot
  entered
  resume =
    provisioningPublishAppleSetupManifestInternal
      (Just (entered, resume))
      writer
      setup
      installRoot

provisioningPublishAppleSetupManifestInternal ::
  Maybe (MVar (), MVar ()) ->
  EngineWriter w s q ->
  ApplePoetrySetupId ->
  FilePath ->
  ProvisioningSession s ()
provisioningPublishAppleSetupManifestInternal
  pauseAfterStaging
  (EngineWriter _ _ engineRoot)
  (ApplePoetrySetupId setup)
  installRoot =
    ProvisioningSession $ do
      authorizedInstallRoot <-
        authorizedWriterPath
          "Apple setup bootstrap root"
          engineRoot
          installRoot
      let manifestPath = authorizedInstallRoot </> "bootstrap.json"
          stagingPath = authorizedInstallRoot </> ".bootstrap.json.incoming"
          contents = appleSetupManifestBytes setup
      existing <-
        try @IOException
          ( readAuthorizedRegularFile
              "Apple setup bootstrap manifest"
              engineRoot
              manifestPath
              (fromIntegral (ByteString.length contents))
          )
      case existing of
        Right installed
          | installed == contents -> pure ()
          | otherwise ->
              ioError
                (userError "Apple setup bootstrap manifest disagrees with its closed adapter")
        Left failure
          | not (isDoesNotExistError failure) -> ioError failure
          | otherwise -> do
              reconcileAppleSetupManifestStaging engineRoot stagingPath
              stagingStatus <-
                withAuthorizedLeafParent
                  "Apple setup bootstrap staging"
                  engineRoot
                  stagingPath
                  ( \parentDescriptor leaf -> do
                      descriptor <-
                        openFdAt
                          (Just parentDescriptor)
                          leaf
                          WriteOnly
                          defaultFileFlags
                            { exclusive = True,
                              nofollow = True,
                              creat =
                                Just
                                  ( Posix.ownerReadMode
                                      .|. Posix.ownerWriteMode
                                  ),
                              cloexec = True
                            }
                      finallyPreservingPrimary
                        ( do
                            status <- Posix.getFdStatus descriptor
                            unless
                              (Posix.isRegularFile status && Posix.fileSize status == 0)
                              (ioError (userError "Apple setup staging file is not new and regular"))
                            writeProvisioningDescriptor descriptor contents
                            fileSynchronise descriptor
                            finalStatus <- Posix.getFdStatus descriptor
                            reopenedStatus <-
                              reopenFileEntryStatus parentDescriptor leaf
                            unless
                              ( stableExecutableStatus status finalStatus
                                  && stableExecutableStatus
                                    finalStatus
                                    reopenedStatus
                              )
                              (ioError (userError "Apple setup staging file changed"))
                            fileSynchronise parentDescriptor
                            pure finalStatus
                        )
                        (closeFd descriptor)
                  )
              case pauseAfterStaging of
                Nothing -> pure ()
                Just (entered, resume) -> do
                  putMVar entered ()
                  takeMVar resume
              stagingComponents <-
                authorizedWriterRelativeComponents
                  "Apple setup bootstrap staging"
                  engineRoot
                  stagingPath
              manifestComponents <-
                authorizedWriterRelativeComponents
                  "Apple setup bootstrap manifest"
                  engineRoot
                  manifestPath
              unless
                (init stagingComponents == init manifestComponents)
                (ioError (userError "Apple setup bootstrap paths are not siblings"))
              runAuthorizedFilesystemMutation
                "Apple setup bootstrap publication"
                engineRoot
                ( Subprocess.provisioningRenameSiblingRegularFile
                    (authorizedWriterMutationRoot engineRoot)
                    (init stagingComponents)
                    (last stagingComponents)
                    (last manifestComponents)
                )
              published <-
                readAuthorizedRegularFile
                  "published Apple setup bootstrap manifest"
                  engineRoot
                  manifestPath
                  (fromIntegral (ByteString.length contents))
              publishedStatus <-
                observeAuthorizedPathStatus
                  "published Apple setup bootstrap manifest"
                  engineRoot
                  manifestPath
              unless
                ( published == contents
                    && maybe
                      False
                      (sameFileObject stagingStatus)
                      publishedStatus
                )
                (ioError (userError "published Apple setup bootstrap manifest changed"))
      validateWriterRootIdentity
        "Apple setup bootstrap publication"
        engineRoot

appleSetupManifestBytes ::
  Internal.ApplePoetrySetupId ->
  ByteString.ByteString
appleSetupManifestBytes setup =
  TextEncoding.encodeUtf8
    ( "{\"adapterId\":\""
        <> Text.pack (Internal.applePoetryAdapterSlug setup)
        <> "\",\"schemaVersion\":1}\n"
    )

reconcileAppleSetupManifestStaging ::
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
reconcileAppleSetupManifestStaging engineRoot stagingPath = do
  observed <-
    observeAuthorizedPathStatus
      "Apple setup bootstrap staging"
      engineRoot
      stagingPath
  case observed of
    Nothing -> pure ()
    Just status
      | Posix.isRegularFile status -> do
          components <-
            authorizedWriterRelativeComponents
              "Apple setup bootstrap staging"
              engineRoot
              stagingPath
          runAuthorizedFilesystemMutation
            "Apple setup bootstrap staging recovery"
            engineRoot
            ( Subprocess.provisioningRemoveTreeLeaf
                (authorizedWriterMutationRoot engineRoot)
                (init components)
                (last components)
            )
      | otherwise ->
          ioError
            (userError "Apple setup bootstrap staging entry is not a regular file")

provisioningLegacyAppleRuntimeBridgeInfo ::
  EngineWriter w s q ->
  ProvisioningSession s (Maybe ProvisioningPathInfo)
provisioningLegacyAppleRuntimeBridgeInfo
  (EngineWriter _ _ engineRoot) =
    ProvisioningSession $
      fmap pathInfoFromStatus
        <$> observeAuthorizedPathStatus
          "legacy Apple runtime bridge"
          engineRoot
          ( authorizedWriterCanonicalRoot engineRoot
              </> "apple-metal-runtime-bridge"
          )

provisioningAudiverisCandidateInfo ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s (Maybe ProvisioningPathInfo)
provisioningAudiverisCandidateInfo
  (EngineWriter _ _ engineRoot)
  parentRoot =
    ProvisioningSession $
      fmap pathInfoFromStatus
        <$> observeAuthorizedPathStatus
          "Audiveris candidate"
          engineRoot
          parentRoot

provisioningAudiverisMountInfo ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s (Maybe ProvisioningPathInfo)
provisioningAudiverisMountInfo
  (EngineWriter _ _ engineRoot)
  parentRoot =
    ProvisioningSession $
      fmap pathInfoFromStatus
        <$> observeAuthorizedPathStatus
          "Audiveris private mount"
          engineRoot
          (parentRoot </> "tmp" </> "audiveris-dmg")

provisioningAudiverisMountedAppPresent ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s Bool
provisioningAudiverisMountedAppPresent
  (EngineWriter _ _ engineRoot)
  parentRoot =
    ProvisioningSession $ do
      observed <-
        observeAuthorizedPathStatus
          "Audiveris mounted application"
          engineRoot
          (parentRoot </> "tmp" </> "audiveris-dmg" </> "Audiveris.app")
      pure (maybe False Posix.isDirectory observed)

provisioningReadAudiverisActivity ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ByteString.ByteString
provisioningReadAudiverisActivity
  (EngineWriter _ _ engineRoot)
  parentRoot =
    ProvisioningSession
      ( readAuthorizedRegularFile
          "Audiveris mount activity"
          engineRoot
          (parentRoot </> ".audiveris-mount-activity.json")
          16384
      )

provisioningCopyAudiverisMountedApp ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s InstalledRuntimeSource
provisioningCopyAudiverisMountedApp writer parentRoot = do
  sourceRoot <-
    authorizeEnginePath
      "Audiveris mounted application source"
      writer
      (parentRoot </> "tmp" </> "audiveris-dmg" </> "Audiveris.app")
  sourceIdentity <-
    ProvisioningSession
      ( resolvePackageClosureIdentity
          Internal.ProvisioningArtifactRootClosure
          sourceRoot
      )
  copyExactPackageClosure
    writer
    sourceIdentity
    (parentRoot </> "Audiveris.app")

provisioningRetireAudiverisStaging ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningRetireAudiverisStaging
  (EngineWriter _ _ engineRoot)
  candidateRoot =
    ProvisioningSession $ do
      components <-
        authorizedWriterRelativeComponents
          "Audiveris staging retirement"
          engineRoot
          (candidateRoot </> "tmp")
      runAuthorizedFilesystemMutation
        "Audiveris staging retirement"
        engineRoot
        ( Subprocess.provisioningRemoveTreeLeaf
            (authorizedWriterMutationRoot engineRoot)
            (init components)
            (last components)
        )

authorizedWriterPath ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO FilePath
authorizedWriterPath label authorizedRoot requestedPath = do
  let configuredRoot = authorizedWriterConfiguredRoot authorizedRoot
      canonicalRoot = authorizedWriterCanonicalRoot authorizedRoot
      normalRequested = normalise requestedPath
      rawComponents = splitDirectories requestedPath
      relativePath
        | writerPathWithin configuredRoot normalRequested =
            makeRelative configuredRoot normalRequested
        | writerPathWithin canonicalRoot normalRequested =
            makeRelative canonicalRoot normalRequested
        | otherwise = ""
      components =
        filter
          (\component -> component /= "/" && component /= ".")
          (splitDirectories relativePath)
      canonicalPath = canonicalRoot </> relativePath
  unless
    ( isAbsolute requestedPath
        && '\NUL' `notElem` requestedPath
        && not (null relativePath)
        && relativePath /= "."
        && not (isAbsolute relativePath)
        && ".." `notElem` rawComponents
        && ".." `notElem` components
        && writerPathWithin canonicalRoot canonicalPath
    )
    (ioError (userError (label <> " escaped its authorized writer root")))
  validateWriterRootIdentity label authorizedRoot
  validateWriterParentAncestry
    label
    (authorizedWriterRootDescriptor authorizedRoot)
    (if null components then [] else init components)
  validateWriterRootIdentity label authorizedRoot
  pure canonicalPath

writerPathWithin :: FilePath -> FilePath -> Bool
writerPathWithin root path =
  let normalRoot = normalise root
      normalPath = normalise path
   in normalPath == normalRoot
        || (normalRoot <> "/") `List.isPrefixOf` (normalPath <> "/")

validateWriterRootIdentity ::
  String ->
  AuthorizedWriterRoot ->
  IO ()
validateWriterRootIdentity label authorizedRoot = do
  descriptorStatus <-
    Posix.getFdStatus
      (authorizedWriterRootDescriptor authorizedRoot)
  pathStatus <-
    Posix.getSymbolicLinkStatus
      (authorizedWriterCanonicalRoot authorizedRoot)
  unless
    ( Posix.isDirectory descriptorStatus
        && not (Posix.isSymbolicLink pathStatus)
        && sameFileObject
          (authorizedWriterRootStatus authorizedRoot)
          descriptorStatus
        && sameFileObject descriptorStatus pathStatus
    )
    (ioError (userError (label <> " writer root identity changed")))

validateWriterParentAncestry ::
  String ->
  Fd ->
  [FilePath] ->
  IO ()
validateWriterParentAncestry label =
  walk
  where
    walk _ [] = pure ()
    walk parentDescriptor (component : remaining) = do
      opened <-
        try @IOException
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
      case opened of
        Left failure
          | isDoesNotExistError failure -> pure ()
          | otherwise ->
              ioError
                ( userError
                    ( label
                        <> " ancestry is not descriptor-contained: "
                        <> displayException failure
                    )
                )
        Right childDescriptor ->
          finallyPreservingPrimary
            ( do
                status <- Posix.getFdStatus childDescriptor
                unless
                  (Posix.isDirectory status)
                  (ioError (userError (label <> " ancestry contains a non-directory")))
                walk childDescriptor remaining
            )
            (closeFd childDescriptor)

observeAuthorizedPathStatus ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO (Maybe Posix.FileStatus)
observeAuthorizedPathStatus label authorizedRoot requestedPath = do
  observed <-
    try @IOException $
      withAuthorizedLeafParent
        label
        authorizedRoot
        requestedPath
        ( \parentDescriptor leaf -> do
            descriptor <-
              openFdAt
                (Just parentDescriptor)
                leaf
                ReadOnly
                defaultFileFlags
                  { nofollow = True,
                    nonBlock = True,
                    cloexec = True
                  }
            finallyPreservingPrimary
              ( do
                  status <- Posix.getFdStatus descriptor
                  finalStatus <- Posix.getFdStatus descriptor
                  unless
                    (stableExecutableStatus status finalStatus)
                    (ioError (userError (label <> " changed during descriptor observation")))
                  pure status
              )
              (closeFd descriptor)
        )
  case observed of
    Left failure
      | isDoesNotExistError failure -> pure Nothing
      | otherwise -> throwIO failure
    Right status -> pure (Just status)

readAuthorizedRegularFile ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  Integer ->
  IO ByteString.ByteString
readAuthorizedRegularFile label authorizedRoot requestedPath maximumBytes
  | maximumBytes <= 0 =
      ioError (userError (label <> " read bound must be positive"))
  | otherwise =
      withAuthorizedLeafParent
        label
        authorizedRoot
        requestedPath
        ( \parentDescriptor leaf -> do
            descriptor <-
              openFdAt
                (Just parentDescriptor)
                leaf
                ReadOnly
                defaultFileFlags
                  { nofollow = True,
                    nonBlock = True,
                    cloexec = True
                  }
            finallyPreservingPrimary
              ( do
                  status <- Posix.getFdStatus descriptor
                  let fileBytes = fromIntegral (Posix.fileSize status)
                  unless
                    ( Posix.isRegularFile status
                        && fileBytes >= 0
                        && fileBytes <= maximumBytes
                    )
                    (ioError (userError (label <> " is not a bounded regular file")))
                  contents <-
                    readExactProvisioningDescriptorBytes descriptor fileBytes
                  finalStatus <- Posix.getFdStatus descriptor
                  reopenedStatus <-
                    reopenFileEntryStatus parentDescriptor leaf
                  unless
                    ( ByteString.length contents == fromIntegral fileBytes
                        && stableExecutableStatus status finalStatus
                        && stableExecutableStatus finalStatus reopenedStatus
                    )
                    (ioError (userError (label <> " changed during descriptor read")))
                  pure contents
              )
              (closeFd descriptor)
        )

withAuthorizedLeafParent ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  (Fd -> FilePath -> IO result) ->
  IO result
withAuthorizedLeafParent
  label
  authorizedRoot
  requestedPath
  action =
    mask $ \restore -> do
      components <-
        authorizedWriterRelativeComponents
          label
          authorizedRoot
          requestedPath
      let parentComponents = init components
          leaf = last components
      rootDescriptor <-
        dup (authorizedWriterRootDescriptor authorizedRoot)
      setFdOption rootDescriptor CloseOnExec True
      finallyPreservingPrimary
        ( restore
            (walk rootDescriptor parentComponents leaf)
        )
        (closeFd rootDescriptor)
    where
      walk parentDescriptor components leaf =
        case components of
          [] -> do
            parentStatus <- Posix.getFdStatus parentDescriptor
            result <- action parentDescriptor leaf
            finalParentStatus <- Posix.getFdStatus parentDescriptor
            unless
              ( Posix.isDirectory parentStatus
                  && stableExecutableStatus parentStatus finalParentStatus
              )
              (ioError (userError (label <> " parent changed during descriptor use")))
            validateWriterRootIdentity label authorizedRoot
            pure result
          component : remaining -> do
            childDescriptor <-
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
                  childStatus <- Posix.getFdStatus childDescriptor
                  unless
                    (Posix.isDirectory childStatus)
                    (ioError (userError (label <> " ancestry is not a directory")))
                  walk childDescriptor remaining leaf
              )
              (closeFd childDescriptor)

authorizedWriterRelativeComponents ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO [FilePath]
authorizedWriterRelativeComponents label authorizedRoot requestedPath = do
  let configuredRoot = authorizedWriterConfiguredRoot authorizedRoot
      canonicalRoot = authorizedWriterCanonicalRoot authorizedRoot
      normalRequested = normalise requestedPath
      relativePath
        | writerPathWithin configuredRoot normalRequested =
            makeRelative configuredRoot normalRequested
        | writerPathWithin canonicalRoot normalRequested =
            makeRelative canonicalRoot normalRequested
        | otherwise = ""
      components =
        filter
          (\component -> component /= "/" && component /= ".")
          (splitDirectories relativePath)
  unless
    ( isAbsolute requestedPath
        && normalise requestedPath == requestedPath
        && '\NUL' `notElem` requestedPath
        && not (null components)
        && not (isAbsolute relativePath)
        && all validFixedPathComponent components
        && ".." `notElem` components
    )
    (ioError (userError (label <> " escaped its authorized root")))
  validateWriterRootIdentity label authorizedRoot
  pure components

authorizeEnginePath ::
  String ->
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s FilePath
authorizeEnginePath label (EngineWriter _ _ authorizedRoot) path =
  ProvisioningSession
    (authorizedWriterPath label authorizedRoot path)

authorizeProjectPath ::
  String ->
  ProjectWriter p s q ->
  FilePath ->
  ProvisioningSession s FilePath
authorizeProjectPath label (ProjectWriter _ authorizedRoot) path =
  ProvisioningSession
    (authorizedWriterPath label authorizedRoot path)

authorizeGeneratedBindingsPath ::
  String ->
  GeneratedBindingsWriter g s q ->
  FilePath ->
  ProvisioningSession s FilePath
authorizeGeneratedBindingsPath
  label
  (GeneratedBindingsWriter _ authorizedRoot outputRoot)
  path
    | writerPathWithin outputRoot path =
        ProvisioningSession
          (authorizedWriterPath label authorizedRoot path)
    | otherwise =
        failProvisioningSession
          (label <> " escaped the fixed generated bindings root")

provisioningCreateDirectory ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningCreateDirectory (EngineWriter _ _ authorizedRoot) path =
  ProvisioningSession
    ( ensureAuthorizedDirectoryTree
        "engine directory creation"
        authorizedRoot
        path
    )

provisioningProjectCreateDirectory ::
  ProjectWriter p s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningProjectCreateDirectory (ProjectWriter _ authorizedRoot) path =
  ProvisioningSession
    ( ensureAuthorizedDirectoryTree
        "project directory creation"
        authorizedRoot
        path
    )

provisioningCreateGeneratedBindingNamespaces ::
  GeneratedBindingsWriter g s q ->
  ProvisioningSession s ()
provisioningCreateGeneratedBindingNamespaces writer = do
  let GeneratedBindingsWriter _ _ outputRoot = writer
      namespaces =
        [ outputRoot,
          outputRoot </> "infernix",
          outputRoot </> "infernix" </> "manifest",
          outputRoot </> "infernix" </> "runtime"
        ]
  mapM_ (createNamespace writer) namespaces
  case writer of
    GeneratedBindingsWriter _ authorizedRoot _ ->
      ProvisioningSession
        ( validateWriterRootIdentity
            "generated binding namespace publication"
            authorizedRoot
        )
  where
    createNamespace bindingsWriter directory = do
      case bindingsWriter of
        GeneratedBindingsWriter _ authorizedRoot outputRoot
          | writerPathWithin outputRoot directory ->
              ProvisioningSession
                ( ensureAuthorizedDirectoryTree
                    "generated binding namespace"
                    authorizedRoot
                    directory
                )
          | otherwise ->
              failProvisioningSession
                "generated binding namespace escaped its fixed output root"
      let initPath = directory </> "__init__.py"
      case bindingsWriter of
        GeneratedBindingsWriter _ authorizedRoot _ ->
          ProvisioningSession
            ( ensureAuthorizedEmptyRegularFile
                "generated binding namespace marker"
                authorizedRoot
                initPath
            )

provisioningRemovePath ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningRemovePath (EngineWriter _ _ authorizedRoot) path =
  ProvisioningSession $ do
    components <-
      authorizedWriterRelativeComponents
        "engine path removal"
        authorizedRoot
        path
    runAuthorizedFilesystemMutation
      "engine path removal"
      authorizedRoot
      ( Subprocess.provisioningRemoveTreeLeaf
          (authorizedWriterMutationRoot authorizedRoot)
          (init components)
          (last components)
      )

provisioningRenameFile ::
  EngineWriter w s q ->
  FilePath ->
  FilePath ->
  ProvisioningSession s ()
provisioningRenameFile (EngineWriter _ _ authorizedRoot) source destination =
  ProvisioningSession $ do
    sourceComponents <-
      authorizedWriterRelativeComponents
        "engine rename source"
        authorizedRoot
        source
    destinationComponents <-
      authorizedWriterRelativeComponents
        "engine rename destination"
        authorizedRoot
        destination
    unless
      (init sourceComponents == init destinationComponents)
      (ioError (userError "engine rename requires sibling regular files"))
    runAuthorizedFilesystemMutation
      "engine sibling-regular-file rename"
      authorizedRoot
      ( Subprocess.provisioningRenameSiblingRegularFile
          (authorizedWriterMutationRoot authorizedRoot)
          (init sourceComponents)
          (last sourceComponents)
          (last destinationComponents)
      )

ensureAuthorizedDirectoryTree ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
ensureAuthorizedDirectoryTree label authorizedRoot requestedPath = do
  components <-
    authorizedWriterRelativeComponents
      label
      authorizedRoot
      requestedPath
  createComponents [] components
  where
    createComponents _ [] =
      validateWriterRootIdentity label authorizedRoot
    createComponents parentComponents (leaf : remaining) = do
      let currentPath =
            authorizedWriterCanonicalRoot authorizedRoot
              </> joinPath (parentComponents <> [leaf])
      observed <-
        observeAuthorizedPathStatus
          label
          authorizedRoot
          currentPath
      case observed of
        Just status ->
          unless
            (Posix.isDirectory status)
            (ioError (userError (label <> " encountered a non-directory")))
        Nothing ->
          runAuthorizedFilesystemMutation
            label
            authorizedRoot
            ( Subprocess.provisioningCreateDirectoryLeaf
                (authorizedWriterMutationRoot authorizedRoot)
                parentComponents
                leaf
            )
      finalStatus <-
        observeAuthorizedPathStatus
          label
          authorizedRoot
          currentPath
      unless
        (maybe False Posix.isDirectory finalStatus)
        (ioError (userError (label <> " did not publish a real directory")))
      createComponents (parentComponents <> [leaf]) remaining

ensureAuthorizedEmptyRegularFile ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
ensureAuthorizedEmptyRegularFile label authorizedRoot requestedPath = do
  observed <-
    observeAuthorizedPathStatus
      label
      authorizedRoot
      requestedPath
  case observed of
    Just status ->
      unless
        ( Posix.isRegularFile status
            && Posix.fileSize status == 0
        )
        (ioError (userError (label <> " is not an empty regular file")))
    Nothing ->
      withAuthorizedLeafParent
        label
        authorizedRoot
        requestedPath
        ( \parentDescriptor leaf -> do
            descriptor <-
              openFdAt
                (Just parentDescriptor)
                leaf
                WriteOnly
                defaultFileFlags
                  { exclusive = True,
                    nofollow = True,
                    creat =
                      Just
                        ( Posix.ownerReadMode
                            .|. Posix.ownerWriteMode
                        ),
                    cloexec = True
                  }
            finallyPreservingPrimary
              ( do
                  status <- Posix.getFdStatus descriptor
                  unless
                    ( Posix.isRegularFile status
                        && Posix.fileSize status == 0
                    )
                    (ioError (userError (label <> " creation produced an invalid file")))
                  fileSynchronise descriptor
                  fileSynchronise parentDescriptor
              )
              (closeFd descriptor)
        )
  finalStatus <-
    observeAuthorizedPathStatus
      label
      authorizedRoot
      requestedPath
  unless
    ( maybe
        False
        (\status -> Posix.isRegularFile status && Posix.fileSize status == 0)
        finalStatus
    )
    (ioError (userError (label <> " publication was not durable")))

runAuthorizedFilesystemMutation ::
  String ->
  AuthorizedWriterRoot ->
  Either
    Subprocess.ProvisioningFilesystemMutationOutcome
    Subprocess.ProvisioningFilesystemMutation ->
  IO ()
runAuthorizedFilesystemMutation label authorizedRoot mutationResult = do
  mutation <-
    case mutationResult of
      Left outcome ->
        ioError
          ( userError
              ( label
                  <> " specification rejected: "
                  <> renderProvisioningMutationOutcome outcome
              )
          )
      Right command -> pure command
  outcome <-
    Subprocess.runProvisioningFilesystemMutation
      (authorizedWriterEnvironment authorizedRoot)
      provisioningFilesystemMutationTimeout
      mutation
  case outcome of
    Subprocess.ProvisioningMutationSucceeded ->
      validateWriterRootIdentity label authorizedRoot
    _ ->
      ioError
        ( userError
            ( label
                <> " failed: "
                <> renderProvisioningMutationOutcome outcome
            )
        )

provisioningFilesystemMutationTimeout :: Subprocess.Timeout
provisioningFilesystemMutationTimeout =
  Subprocess.Timeout (120 * 1000 * 1000)

renderProvisioningMutationOutcome ::
  Subprocess.ProvisioningFilesystemMutationOutcome ->
  String
renderProvisioningMutationOutcome outcome =
  case outcome of
    Subprocess.ProvisioningMutationSucceeded -> "succeeded"
    Subprocess.ProvisioningMutationRejectedSpec failure ->
      "rejected: " <> Text.unpack failure
    Subprocess.ProvisioningMutationKernelFailure failure ->
      "kernel failure: " <> Text.unpack failure
    Subprocess.ProvisioningMutationTimedOut timeout ->
      "timed out after "
        <> show (Subprocess.timeoutMicros timeout)
        <> " microseconds"

data StableFileCopyEvidence s = StableFileCopyEvidence
  { stableFileCopyDigest :: !Text,
    stableFileCopyInfo :: !ProvisioningPathInfo
  }

type role StableFileCopyEvidence nominal

provisioningCopyFileStable ::
  EngineWriter w s q ->
  FilePath ->
  FilePath ->
  ProvisioningSession s (StableFileCopyEvidence s)
provisioningCopyFileStable writer =
  provisioningCopyFileStableBounded
    writer
    maximumStableCopyBytes

provisioningCopyFileStableBounded ::
  EngineWriter w s q ->
  Integer ->
  FilePath ->
  FilePath ->
  ProvisioningSession s (StableFileCopyEvidence s)
provisioningCopyFileStableBounded
  (EngineWriter _ _ authorizedRoot)
  maximumBytes
  source
  destination
    | maximumBytes <= 0
        || maximumBytes > maximumStableCopyBytes =
        failProvisioningSession
          "stable copy bound must be positive and no greater than 2147483648 bytes"
    | otherwise =
        ProvisioningSession $ do
          authorizedSource <-
            authorizedWriterPath
              "stable copy source"
              authorizedRoot
              source
          authorizedDestination <-
            authorizedWriterPath
              "stable copy destination"
              authorizedRoot
              destination
          copied <-
            copyRegularFileStable
              maximumBytes
              authorizedSource
              authorizedDestination
          validateWriterRootIdentity "stable copy" authorizedRoot
          pure copied

maximumStableCopyBytes :: Integer
maximumStableCopyBytes = 2 * 1024 * 1024 * 1024

copyRegularFileStable ::
  Integer ->
  FilePath ->
  FilePath ->
  IO (StableFileCopyEvidence s)
copyRegularFileStable maximumBytes source destination =
  mask $ \restore -> do
    listedStatus <- Posix.getSymbolicLinkStatus source
    unless
      ( Posix.isRegularFile listedStatus
          && not (Posix.isSymbolicLink listedStatus)
          && fromIntegral (Posix.fileSize listedStatus)
            <= maximumBytes
      )
      (ioError (userError ("stable copy source is invalid: " <> source)))
    sourceDescriptor <-
      openFd
        source
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( do
          openedStatus <- Posix.getFdStatus sourceDescriptor
          unless
            (stableExecutableStatus listedStatus openedStatus)
            (ioError (userError ("stable copy source changed before open: " <> source)))
          destinationDescriptor <-
            openFd
              destination
              ReadWrite
              defaultFileFlags
                { exclusive = True,
                  nofollow = True,
                  creat =
                    Just
                      ( Posix.ownerReadMode
                          .|. Posix.ownerWriteMode
                      ),
                  cloexec = True
                }
          destinationOpenedStatus <-
            onExceptionPreservingPrimary
              (Posix.getFdStatus destinationDescriptor)
              (closeFd destinationDescriptor)
          let cleanupDestination = do
                _ <- try @IOException (closeFd destinationDescriptor)
                removeStableDestinationIfOwned
                  destination
                  destinationOpenedStatus
                synchroniseProvisioningDirectory (takeDirectory destination)
          onExceptionPreservingPrimary
            ( finallyPreservingPrimary
                ( do
                    unless
                      (Posix.isRegularFile destinationOpenedStatus)
                      (ioError (userError ("stable copy destination is not regular: " <> destination)))
                    (copiedBytes, sourceContext) <-
                      restore $ do
                        copyProvisioningDescriptor
                          sourceDescriptor
                          destinationDescriptor
                          0
                          SHA256.init
                          maximumBytes
                    finalSourceStatus <-
                      Posix.getFdStatus sourceDescriptor
                    finalPathStatus <-
                      Posix.getSymbolicLinkStatus source
                    let sourceDigest =
                          "sha256:"
                            <> TextEncoding.decodeUtf8
                              (Base16.encode (SHA256.finalize sourceContext))
                        sourceExecutable =
                          Posix.fileMode listedStatus
                            .&. ( Posix.ownerExecuteMode
                                    .|. Posix.groupExecuteMode
                                    .|. Posix.otherExecuteMode
                                )
                            /= 0
                        destinationMode =
                          Posix.ownerReadMode
                            .|. ( if sourceExecutable
                                    then Posix.ownerExecuteMode
                                    else 0
                                )
                    unless
                      ( copiedBytes
                          == fromIntegral (Posix.fileSize listedStatus)
                          && stableExecutableStatus
                            openedStatus
                            finalSourceStatus
                          && stableExecutableStatus
                            finalSourceStatus
                            finalPathStatus
                      )
                      (ioError (userError ("stable copy source changed while copying: " <> source)))
                    Posix.setFdMode destinationDescriptor destinationMode
                    fileSynchronise destinationDescriptor
                    _ <- fdSeek destinationDescriptor AbsoluteSeek 0
                    destinationContext <-
                      restore
                        (hashExecutableDescriptor SHA256.init destinationDescriptor)
                    stableDestinationStatus <-
                      Posix.getFdStatus destinationDescriptor
                    destinationStatus <-
                      Posix.getSymbolicLinkStatus destination
                    finalDestinationStatus <-
                      Posix.getFdStatus destinationDescriptor
                    let destinationDigest =
                          "sha256:"
                            <> TextEncoding.decodeUtf8
                              (Base16.encode (SHA256.finalize destinationContext))
                    unless
                      ( Posix.isRegularFile stableDestinationStatus
                          && sameFileObject
                            destinationOpenedStatus
                            stableDestinationStatus
                          && stableExecutableStatus
                            stableDestinationStatus
                            destinationStatus
                          && stableExecutableStatus
                            destinationStatus
                            finalDestinationStatus
                          && Posix.fileMode stableDestinationStatus
                            .&. Posix.accessModes
                            == destinationMode
                          && Posix.fileSize stableDestinationStatus
                            == Posix.fileSize listedStatus
                          && destinationDigest == sourceDigest
                      )
                      (ioError (userError ("stable copy destination disagreed: " <> destination)))
                    synchroniseProvisioningDirectory
                      (takeDirectory destination)
                    pure
                      StableFileCopyEvidence
                        { stableFileCopyDigest = destinationDigest,
                          stableFileCopyInfo =
                            pathInfoFromStatus stableDestinationStatus
                        }
                )
                (closeFd destinationDescriptor)
            )
            cleanupDestination
      )
      (closeFd sourceDescriptor)

sameFileObject :: Posix.FileStatus -> Posix.FileStatus -> Bool
sameFileObject expected observed =
  Posix.deviceID expected == Posix.deviceID observed
    && Posix.fileID expected == Posix.fileID observed

removeStableDestinationIfOwned ::
  FilePath ->
  Posix.FileStatus ->
  IO ()
removeStableDestinationIfOwned destination expected = do
  observed <- try @IOException (Posix.getSymbolicLinkStatus destination)
  case observed of
    Right status
      | sameFileObject expected status ->
          Directory.removeFile destination
    _ -> pure ()

copyProvisioningDescriptor ::
  Fd ->
  Fd ->
  Integer ->
  SHA256.Ctx ->
  Integer ->
  IO (Integer, SHA256.Ctx)
copyProvisioningDescriptor source destination copiedBytes context maximumBytes = do
  chunk <- PosixByteString.fdRead source (64 * 1024)
  if ByteString.null chunk
    then pure (copiedBytes, context)
    else do
      let nextBytes =
            copiedBytes + fromIntegral (ByteString.length chunk)
      unless
        (nextBytes <= maximumBytes)
        (ioError (userError "stable copy exceeded its fixed byte bound"))
      writeProvisioningDescriptor destination chunk
      copyProvisioningDescriptor
        source
        destination
        nextBytes
        (SHA256.update context chunk)
        maximumBytes

writeProvisioningDescriptor :: Fd -> ByteString.ByteString -> IO ()
writeProvisioningDescriptor descriptor contents
  | ByteString.null contents = pure ()
  | otherwise = do
      written <- PosixByteString.fdWrite descriptor contents
      unless
        (written > 0)
        (ioError (userError "stable descriptor write made no progress"))
      writeProvisioningDescriptor
        descriptor
        (ByteString.drop (fromIntegral written) contents)

provisioningCanonicalizePath :: FilePath -> ProvisioningSession s FilePath
provisioningCanonicalizePath =
  ProvisioningSession . Directory.canonicalizePath

provisioningInstallAppleNativeRunnerLibrary ::
  EngineWriter w s q ->
  Paths ->
  FilePath ->
  ProvisioningSession s ()
provisioningInstallAppleNativeRunnerLibrary
  writer
  paths
  candidateRoot
    | not (isAbsolute (repoRoot paths) && isAbsolute candidateRoot) =
        failProvisioningSession
          "Apple native runner library roots must be absolute"
    | otherwise = do
        let sourcePath =
              repoRoot paths
                </> "python"
                </> "native-runners"
                </> "apple_native_runner.py"
            destinationPath =
              candidateRoot
                </> "lib"
                </> "apple_native_runner.py"
        provisioningCreateDirectory writer (takeDirectory destinationPath)
        ProvisioningSession $ do
          let EngineWriter _ _ authorizedRoot = writer
          authorizedDestination <-
            authorizedWriterPath
              "Apple native runner library destination"
              authorizedRoot
              destinationPath
          _ <-
            copyRegularFileStable
              (1024 * 1024)
              sourcePath
              authorizedDestination
          validateWriterRootIdentity
            "Apple native runner library installation"
            authorizedRoot

data DynamicPayloadScan = DynamicPayloadScan
  { dynamicPayloadEntries :: !Integer,
    dynamicPayloadBytes :: !Integer,
    dynamicPayloadPaths :: ![FilePath]
  }

maximumDynamicPayloadEntries :: Integer
maximumDynamicPayloadEntries = 8192

maximumDynamicPayloadBytes :: Integer
maximumDynamicPayloadBytes = 256 * 1024 * 1024

maximumDynamicPayloadDepth :: Int
maximumDynamicPayloadDepth = 32

provisioningListDynamicPayloads ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s [FilePath]
provisioningListDynamicPayloads writer root = do
  authorizedRoot <-
    authorizeEnginePath "dynamic payload scan root" writer root
  ProvisioningSession $ do
    result <- try @IOException (scanDynamicPayloadRoot authorizedRoot)
    case result of
      Left failure
        | isDoesNotExistError failure -> pure []
        | otherwise -> throwIO failure
      Right payloads -> pure payloads

scanDynamicPayloadRoot :: FilePath -> IO [FilePath]
scanDynamicPayloadRoot root =
  mask $ \restore -> do
    listedStatus <- Posix.getSymbolicLinkStatus root
    unless
      ( Posix.isDirectory listedStatus
          && not (Posix.isSymbolicLink listedStatus)
      )
      (ioError (userError "dynamic payload root is not a real directory"))
    descriptor <-
      openFd
        root
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            directory = True,
            cloexec = True
          }
    observed <-
      finallyPreservingPrimary
        ( restore $ do
            openedStatus <- Posix.getFdStatus descriptor
            unless
              (stableExecutableStatus listedStatus openedStatus)
              (ioError (userError "dynamic payload root changed before traversal"))
            state <-
              scanDynamicPayloadDirectory
                root
                descriptor
                openedStatus
                0
                DynamicPayloadScan
                  { dynamicPayloadEntries = 0,
                    dynamicPayloadBytes = 0,
                    dynamicPayloadPaths = []
                  }
            finalStatus <- Posix.getFdStatus descriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus root
            unless
              ( stableExecutableStatus openedStatus finalStatus
                  && stableExecutableStatus finalStatus finalPathStatus
              )
              (ioError (userError "dynamic payload root changed during traversal"))
            pure state
        )
        (closeFd descriptor)
    pure (List.sort (dynamicPayloadPaths observed))

scanDynamicPayloadDirectory ::
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  Int ->
  DynamicPayloadScan ->
  IO DynamicPayloadScan
scanDynamicPayloadDirectory path descriptor listedStatus depth state = do
  unless
    ( depth <= maximumDynamicPayloadDepth
        && dynamicPayloadEntries state
          <= maximumDynamicPayloadEntries
    )
    (ioError (userError "dynamic payload traversal exceeds its fixed bound"))
  entries <-
    listDirectoryBoundedFromDescriptor
      descriptor
      ( maximumDynamicPayloadEntries
          - dynamicPayloadEntries state
      )
  observed <-
    foldM
      (scanDynamicPayloadEntry path descriptor depth)
      state
      entries
  finalStatus <- Posix.getFdStatus descriptor
  unless
    (stableExecutableStatus listedStatus finalStatus)
    (ioError (userError "dynamic payload directory changed during traversal"))
  pure observed

scanDynamicPayloadEntry ::
  FilePath ->
  Fd ->
  Int ->
  DynamicPayloadScan ->
  FilePath ->
  IO DynamicPayloadScan
scanDynamicPayloadEntry parent parentDescriptor depth state entry = do
  let path = parent </> entry
      countedState =
        state
          { dynamicPayloadEntries =
              dynamicPayloadEntries state + 1
          }
  unless
    (dynamicPayloadEntries countedState <= maximumDynamicPayloadEntries)
    (ioError (userError "dynamic payload traversal exceeds its entry bound"))
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
            status <- Posix.getFdStatus childDescriptor
            observed <-
              scanDynamicPayloadDirectory
                path
                childDescriptor
                status
                (depth + 1)
                countedState
            reopenedStatus <-
              reopenDirectoryEntryStatus parentDescriptor entry
            finalStatus <- Posix.getFdStatus childDescriptor
            unless
              ( stableExecutableStatus status finalStatus
                  && stableExecutableStatus finalStatus reopenedStatus
              )
              (ioError (userError ("dynamic payload directory changed: " <> path)))
            pure observed
        )
        (closeFd childDescriptor)
    Left _ ->
      scanDynamicPayloadFile
        parent
        parentDescriptor
        entry
        path
        countedState

scanDynamicPayloadFile ::
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  DynamicPayloadScan ->
  IO DynamicPayloadScan
scanDynamicPayloadFile parent parentDescriptor entry path state = do
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
            status <- Posix.getFdStatus descriptor
            unless
              (Posix.isRegularFile status)
              (ioError (userError ("dynamic payload entry is unsupported: " <> path)))
            reopenedStatus <- reopenFileEntryStatus parentDescriptor entry
            finalStatus <- Posix.getFdStatus descriptor
            unless
              ( stableExecutableStatus status finalStatus
                  && stableExecutableStatus finalStatus reopenedStatus
              )
              (ioError (userError ("dynamic payload file changed: " <> path)))
            if any (`List.isSuffixOf` entry) [".dylib", ".so"]
              then do
                let nextBytes =
                      dynamicPayloadBytes state
                        + fromIntegral (Posix.fileSize status)
                unless
                  ( fromIntegral (Posix.fileSize status)
                      <= maximumExactRuntimeFileBytes
                      && nextBytes <= maximumDynamicPayloadBytes
                  )
                  (ioError (userError "dynamic payload files exceed their byte bound"))
                pure
                  state
                    { dynamicPayloadBytes = nextBytes,
                      dynamicPayloadPaths =
                        path : dynamicPayloadPaths state
                    }
              else pure state
        )
        (closeFd descriptor)
    Left _ -> do
      parentStatus <- Posix.getFdStatus parentDescriptor
      parentPathStatus <- Posix.getSymbolicLinkStatus parent
      status <- Posix.getSymbolicLinkStatus path
      finalStatus <- Posix.getSymbolicLinkStatus path
      finalParentStatus <- Posix.getFdStatus parentDescriptor
      finalParentPathStatus <- Posix.getSymbolicLinkStatus parent
      unless
        ( Posix.isSymbolicLink status
            && stableExecutableStatus status finalStatus
            && stableExecutableStatus parentStatus parentPathStatus
            && stableExecutableStatus parentStatus finalParentStatus
            && stableExecutableStatus
              finalParentStatus
              finalParentPathStatus
        )
        (ioError (userError ("dynamic payload entry is unsafe: " <> path)))
      pure state

provisioningReadAudiverisBundledJavaVersion ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s Text
provisioningReadAudiverisBundledJavaVersion writer artifactRoot = do
  authorizedArtifactRoot <-
    authorizeEnginePath
      "Audiveris bundled Java root"
      writer
      artifactRoot
  ProvisioningSession $ do
    let releasePath =
          authorizedArtifactRoot
            </> "Audiveris.app"
            </> "Contents"
            </> "runtime"
            </> "Contents"
            </> "Home"
            </> "release"
    releaseBytes <-
      readRegularFileNoFollowBounded releasePath 16384
    releaseText <-
      either
        (ioError . userError . ("Audiveris JVM release metadata is not UTF-8: " <>) . show)
        pure
        (TextEncoding.decodeUtf8' releaseBytes)
    let versionLines =
          [ Text.dropAround
              (== '"')
              (Text.drop (Text.length ("JAVA_VERSION=" :: Text)) line)
          | line <- Text.lines releaseText,
            "JAVA_VERSION=" `Text.isPrefixOf` line
          ]
    case versionLines of
      [version]
        | not (Text.null version) -> pure version
      _ ->
        ioError
          (userError "Audiveris JVM release metadata has no unique JAVA_VERSION")

provisioningAudiverisDmgValid ::
  DownloadCacheWriter d s q ->
  ProvisioningSession s Bool
provisioningAudiverisDmgValid
  writer =
    isJust <$> validateAudiverisDmgReceipt writer

provisioningAudiverisDownloadedDmgValid ::
  DownloadCacheWriter d s q ->
  ProvisioningSession s Bool
provisioningAudiverisDownloadedDmgValid
  (DownloadCacheWriter _ cacheRoot) =
    provisioningAudiverisDmgValidForLeaf
      cacheRoot
      (Recipe.audiverisDmgFileName <> ".download")

validateAudiverisDmgReceipt ::
  DownloadCacheWriter d s q ->
  ProvisioningSession s (Maybe (AudiverisDmgReceipt d s q))
validateAudiverisDmgReceipt
  (DownloadCacheWriter _ cacheRoot) =
    ProvisioningSession $ do
      result <-
        validateAudiverisDmgLeaf
          cacheRoot
          Recipe.audiverisDmgFileName
      pure
        ( fmap
            ( \(status, digest) ->
                AudiverisDmgReceipt
                  { audiverisDmgReceiptStatus = status,
                    audiverisDmgReceiptDigest = digest
                  }
            )
            result
        )

prepareAudiverisDmgDownload ::
  DownloadCacheWriter d s q ->
  ProvisioningSession s ()
prepareAudiverisDmgDownload
  (DownloadCacheWriter _ cacheRoot) =
    ProvisioningSession $
      removeAuthorizedCacheLeaf
        cacheRoot
        (Recipe.audiverisDmgFileName <> ".download")

promoteAudiverisDmgDownload ::
  DownloadCacheWriter d s q ->
  ProvisioningSession s (AudiverisDmgReceipt d s q)
promoteAudiverisDmgDownload
  (DownloadCacheWriter _ cacheRoot) =
    ProvisioningSession $ do
      incoming <-
        validateAudiverisDmgLeaf
          cacheRoot
          (Recipe.audiverisDmgFileName <> ".download")
      case incoming of
        Nothing ->
          ioError
            (userError "downloaded Audiveris DMG has no checksum-bound receipt")
        Just _ -> do
          removeAuthorizedCacheLeaf
            cacheRoot
            Recipe.audiverisDmgFileName
          runAuthorizedFilesystemMutation
            "Audiveris DMG cache promotion"
            cacheRoot
            ( Subprocess.provisioningRenameSiblingRegularFile
                (authorizedWriterMutationRoot cacheRoot)
                []
                (Recipe.audiverisDmgFileName <> ".download")
                Recipe.audiverisDmgFileName
            )
          promoted <-
            validateAudiverisDmgLeaf
              cacheRoot
              Recipe.audiverisDmgFileName
          case promoted of
            Just (status, digest) ->
              pure
                AudiverisDmgReceipt
                  { audiverisDmgReceiptStatus = status,
                    audiverisDmgReceiptDigest = digest
                  }
            Nothing ->
              ioError
                (userError "promoted Audiveris DMG lost its exact receipt")

stageAudiverisDmgForCandidate ::
  DownloadCacheWriter d s q ->
  EngineWriter w s q ->
  AudiverisDmgReceipt d s q ->
  FilePath ->
  ProvisioningSession s (StagedAudiverisDmg w s q)
stageAudiverisDmgForCandidate
  (DownloadCacheWriter _ cacheRoot)
  (EngineWriter _ _ engineRoot)
  receipt
  candidateRoot =
    ProvisioningSession $ do
      _ <-
        authorizedWriterPath
          "Audiveris candidate DMG staging root"
          engineRoot
          candidateRoot
      let stagingRoot = candidateRoot </> "tmp"
          stagedPath = stagingRoot </> Recipe.audiverisDmgFileName
      ensureAuthorizedDirectoryTree
        "Audiveris candidate DMG staging directory"
        engineRoot
        stagingRoot
      components <-
        authorizedWriterRelativeComponents
          "Audiveris staged DMG reset"
          engineRoot
          stagedPath
      runAuthorizedFilesystemMutation
        "Audiveris staged DMG reset"
        engineRoot
        ( Subprocess.provisioningRemoveTreeLeaf
            (authorizedWriterMutationRoot engineRoot)
            (init components)
            (last components)
        )
      (stagedStatus, stagedDigest) <-
        copyAudiverisDmgReceipt
          cacheRoot
          engineRoot
          receipt
          stagedPath
      pure
        StagedAudiverisDmg
          { stagedAudiverisCandidateRoot = candidateRoot,
            stagedAudiverisDmgStatus = stagedStatus,
            stagedAudiverisDmgDigest = stagedDigest
          }

provisioningAudiverisDmgValidForLeaf ::
  AuthorizedWriterRoot ->
  FilePath ->
  ProvisioningSession s Bool
provisioningAudiverisDmgValidForLeaf cacheRoot expectedLeaf =
  ProvisioningSession $
    isJust
      <$> validateAudiverisDmgLeaf cacheRoot expectedLeaf

validateAudiverisDmgLeaf ::
  AuthorizedWriterRoot ->
  FilePath ->
  IO (Maybe (Posix.FileStatus, Text))
validateAudiverisDmgLeaf cacheRoot expectedLeaf = do
  let path =
        authorizedWriterCanonicalRoot cacheRoot
          </> expectedLeaf
  result <-
    try @IOException
      ( digestAuthorizedRegularFileExact
          cacheRoot
          path
          Recipe.audiverisDmgSize
      )
  case result of
    Left failure
      | isDoesNotExistError failure -> pure Nothing
      | otherwise -> throwIO failure
    Right exact@(status, digest)
      | takeFileName path == expectedLeaf
          && Posix.isRegularFile status
          && digest == Recipe.audiverisDmgDigest ->
          pure (Just exact)
      | otherwise -> pure Nothing

removeAuthorizedCacheLeaf ::
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
removeAuthorizedCacheLeaf cacheRoot leaf =
  runAuthorizedFilesystemMutation
    "Audiveris download cache reset"
    cacheRoot
    ( Subprocess.provisioningRemoveTreeLeaf
        (authorizedWriterMutationRoot cacheRoot)
        []
        leaf
    )

digestAuthorizedRegularFileExact ::
  AuthorizedWriterRoot ->
  FilePath ->
  Integer ->
  IO (Posix.FileStatus, Text)
digestAuthorizedRegularFileExact authorizedRoot path expectedBytes =
  withAuthorizedLeafParent
    "exact authorized file digest"
    authorizedRoot
    path
    ( \parentDescriptor leaf -> do
        descriptor <-
          openFdAt
            (Just parentDescriptor)
            leaf
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                nonBlock = True,
                cloexec = True
              }
        finallyPreservingPrimary
          ( do
              status <- Posix.getFdStatus descriptor
              unless
                ( Posix.isRegularFile status
                    && fromIntegral (Posix.fileSize status)
                      == expectedBytes
                )
                (ioError (userError "authorized file has an unexpected type or size"))
              digest <-
                digestExactProvisioningDescriptor descriptor expectedBytes
              finalStatus <- Posix.getFdStatus descriptor
              reopenedStatus <-
                reopenFileEntryStatus parentDescriptor leaf
              unless
                ( stableExecutableStatus status finalStatus
                    && stableExecutableStatus finalStatus reopenedStatus
                )
                (ioError (userError "authorized file changed during exact digest"))
              pure (finalStatus, digest)
          )
          (closeFd descriptor)
    )

copyAudiverisDmgReceipt ::
  AuthorizedWriterRoot ->
  AuthorizedWriterRoot ->
  AudiverisDmgReceipt d s q ->
  FilePath ->
  IO (Posix.FileStatus, Text)
copyAudiverisDmgReceipt cacheRoot engineRoot receipt destination = do
  destinationComponents <-
    authorizedWriterRelativeComponents
      "Audiveris staged DMG"
      engineRoot
      destination
  let source =
        authorizedWriterCanonicalRoot cacheRoot
          </> Recipe.audiverisDmgFileName
      cleanupDestination =
        runAuthorizedFilesystemMutation
          "Audiveris staged DMG cleanup"
          engineRoot
          ( Subprocess.provisioningRemoveTreeLeaf
              (authorizedWriterMutationRoot engineRoot)
              (init destinationComponents)
              (last destinationComponents)
          )
  onExceptionPreservingPrimary
    ( withAuthorizedLeafParent
        "Audiveris checksum-bound cache source"
        cacheRoot
        source
        ( \sourceParent sourceLeaf -> do
            sourceDescriptor <-
              openFdAt
                (Just sourceParent)
                sourceLeaf
                ReadOnly
                defaultFileFlags
                  { nofollow = True,
                    nonBlock = True,
                    cloexec = True
                  }
            finallyPreservingPrimary
              ( do
                  sourceStatus <- Posix.getFdStatus sourceDescriptor
                  unless
                    ( Posix.isRegularFile sourceStatus
                        && stableExecutableStatus
                          (audiverisDmgReceiptStatus receipt)
                          sourceStatus
                        && audiverisDmgReceiptDigest receipt
                          == Recipe.audiverisDmgDigest
                    )
                    (ioError (userError "Audiveris cache receipt changed before staging"))
                  withAuthorizedLeafParent
                    "Audiveris staged DMG destination"
                    engineRoot
                    destination
                    ( \destinationParent destinationLeaf -> do
                        destinationDescriptor <-
                          openFdAt
                            (Just destinationParent)
                            destinationLeaf
                            ReadWrite
                            defaultFileFlags
                              { exclusive = True,
                                nofollow = True,
                                creat =
                                  Just
                                    ( Posix.ownerReadMode
                                        .|. Posix.ownerWriteMode
                                    ),
                                cloexec = True
                              }
                        finallyPreservingPrimary
                          ( do
                              destinationInitial <-
                                Posix.getFdStatus destinationDescriptor
                              unless
                                (Posix.isRegularFile destinationInitial)
                                (ioError (userError "Audiveris staged DMG is not regular"))
                              (copiedBytes, copiedContext) <-
                                copyProvisioningDescriptor
                                  sourceDescriptor
                                  destinationDescriptor
                                  0
                                  SHA256.init
                                  Recipe.audiverisDmgSize
                              sourceFinal <- Posix.getFdStatus sourceDescriptor
                              sourceReopened <-
                                reopenFileEntryStatus sourceParent sourceLeaf
                              let copiedDigest =
                                    "sha256:"
                                      <> TextEncoding.decodeUtf8
                                        (Base16.encode (SHA256.finalize copiedContext))
                              unless
                                ( copiedBytes == Recipe.audiverisDmgSize
                                    && copiedDigest
                                      == audiverisDmgReceiptDigest receipt
                                    && stableExecutableStatus
                                      sourceStatus
                                      sourceFinal
                                    && stableExecutableStatus
                                      sourceFinal
                                      sourceReopened
                                )
                                (ioError (userError "Audiveris cache source changed while staging"))
                              Posix.setFdMode
                                destinationDescriptor
                                Posix.ownerReadMode
                              fileSynchronise destinationDescriptor
                              _ <- fdSeek destinationDescriptor AbsoluteSeek 0
                              stagedDigest <-
                                digestExactProvisioningDescriptor
                                  destinationDescriptor
                                  Recipe.audiverisDmgSize
                              stagedStatus <-
                                Posix.getFdStatus destinationDescriptor
                              stagedReopened <-
                                reopenFileEntryStatus
                                  destinationParent
                                  destinationLeaf
                              unless
                                ( stagedDigest == Recipe.audiverisDmgDigest
                                    && sameFileObject
                                      destinationInitial
                                      stagedStatus
                                    && stableExecutableStatus
                                      stagedStatus
                                      stagedReopened
                                    && fromIntegral
                                      (Posix.fileSize stagedStatus)
                                      == Recipe.audiverisDmgSize
                                )
                                (ioError (userError "Audiveris staged DMG failed exact validation"))
                              fileSynchronise destinationParent
                              pure (stagedStatus, stagedDigest)
                          )
                          (closeFd destinationDescriptor)
                    )
              )
              (closeFd sourceDescriptor)
        )
    )
    cleanupDestination

digestRegularFileNoFollowExact ::
  FilePath ->
  Integer ->
  IO Text
digestRegularFileNoFollowExact path expectedBytes =
  mask $ \restore -> do
    listedStatus <- Posix.getSymbolicLinkStatus path
    unless
      ( Posix.isRegularFile listedStatus
          && not (Posix.isSymbolicLink listedStatus)
          && fromIntegral (Posix.fileSize listedStatus)
            == expectedBytes
      )
      (ioError (userError ("exact digest source is invalid: " <> path)))
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
          openedStatus <- Posix.getFdStatus descriptor
          unless
            (stableExecutableStatus listedStatus openedStatus)
            (ioError (userError ("exact digest source changed before open: " <> path)))
          digest <-
            digestExactProvisioningDescriptor
              descriptor
              expectedBytes
          finalStatus <- Posix.getFdStatus descriptor
          finalPathStatus <- Posix.getSymbolicLinkStatus path
          unless
            ( stableExecutableStatus openedStatus finalStatus
                && stableExecutableStatus finalStatus finalPathStatus
            )
            (ioError (userError ("exact digest source changed while hashing: " <> path)))
          pure digest
      )
      (closeFd descriptor)

maximumRelocationBinEntries :: Integer
maximumRelocationBinEntries = 4096

maximumRelocationBinFileBytes :: Integer
maximumRelocationBinFileBytes = 16 * 1024 * 1024

maximumRelocationConfigBytes :: Integer
maximumRelocationConfigBytes = 64 * 1024

maximumRelocationCandidateEntries :: Integer
maximumRelocationCandidateEntries = 100000

maximumRelocationCandidateBytes :: Integer
maximumRelocationCandidateBytes = 4 * 1024 * 1024 * 1024

relocationCandidateByteBoundForTest :: Integer
relocationCandidateByteBoundForTest =
  maximumRelocationCandidateBytes

validateRelocationCandidateByteSequenceForTest ::
  [Integer] ->
  Either String Integer
validateRelocationCandidateByteSequenceForTest =
  foldM advance 0
  where
    advance total nextBytes
      | nextBytes < 0 =
          Left "candidate relocation byte increment must not be negative"
      | total + nextBytes > maximumRelocationCandidateBytes =
          Left "candidate relocation byte total exceeds its fixed bound"
      | otherwise =
          Right (total + nextBytes)

maximumRelocationCandidateDepth :: Int
maximumRelocationCandidateDepth = 64

provisioningRelocateCandidateVenv ::
  EngineWriter w s q ->
  FilePath ->
  FilePath ->
  ProvisioningSession s ()
provisioningRelocateCandidateVenv
  writer
  installRoot
  candidateRoot
    | not (isAbsolute installRoot && isAbsolute candidateRoot) =
        failProvisioningSession
          "candidate relocation roots must be absolute"
    | normalise candidateRoot
        /= normalise (Artifact.engineArtifactTempRoot installRoot) =
        failProvisioningSession
          "candidate relocation root is not the owned transaction sibling"
    | ByteString.length oldRootBytes > 4096
        || ByteString.length newRootBytes > 4096 =
        failProvisioningSession
          "candidate relocation roots exceed their fixed byte bound"
    | otherwise =
        do
          authorizedInstallRoot <-
            authorizeEnginePath
              "candidate relocation install root"
              writer
              installRoot
          authorizedCandidateRoot <-
            authorizeEnginePath
              "candidate relocation root"
              writer
              candidateRoot
          let authorizedOldRootBytes =
                TextEncoding.encodeUtf8
                  (Text.pack authorizedCandidateRoot)
              authorizedNewRootBytes =
                TextEncoding.encodeUtf8
                  (Text.pack authorizedInstallRoot)
          unless
            ( ByteString.length authorizedOldRootBytes <= 4096
                && ByteString.length authorizedNewRootBytes <= 4096
            )
            ( failProvisioningSession
                "authorized candidate relocation roots exceed their fixed byte bound"
            )
          ProvisioningSession
            ( relocateCandidateVenvExact
                authorizedInstallRoot
                authorizedCandidateRoot
                authorizedOldRootBytes
                authorizedNewRootBytes
            )
    where
      oldRootBytes =
        TextEncoding.encodeUtf8 (Text.pack candidateRoot)
      newRootBytes =
        TextEncoding.encodeUtf8 (Text.pack installRoot)

relocateCandidateVenvExact ::
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  ByteString.ByteString ->
  IO ()
relocateCandidateVenvExact
  installRoot
  candidateRoot
  oldRootBytes
  newRootBytes =
    mask $ \restore -> do
      listedRootStatus <- Posix.getSymbolicLinkStatus candidateRoot
      unless
        ( Posix.isDirectory listedRootStatus
            && not (Posix.isSymbolicLink listedRootStatus)
        )
        (ioError (userError "candidate relocation root is not a real directory"))
      rootDescriptor <-
        openFd
          candidateRoot
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              directory = True,
              cloexec = True
            }
      finallyPreservingPrimary
        ( restore $ do
            openedRootStatus <- Posix.getFdStatus rootDescriptor
            unless
              (stableExecutableStatus listedRootStatus openedRootStatus)
              (ioError (userError "candidate relocation root changed before traversal"))
            withProvisioningDirectoryAt
              rootDescriptor
              candidateRoot
              "venv"
              ( \venvPath venvDescriptor _venvStatus -> do
                  withProvisioningDirectoryAt
                    venvDescriptor
                    venvPath
                    "bin"
                    ( \binPath binDescriptor _binStatus -> do
                        entries <-
                          listDirectoryBoundedFromDescriptor
                            binDescriptor
                            maximumRelocationBinEntries
                        mapM_
                          ( rewriteRelocationEntry
                              binPath
                              binDescriptor
                              maximumRelocationBinFileBytes
                              oldRootBytes
                              newRootBytes
                          )
                          entries
                    )
                  rewriteRelocationEntry
                    venvPath
                    venvDescriptor
                    maximumRelocationConfigBytes
                    oldRootBytes
                    newRootBytes
                    "pyvenv.cfg"
                  sourcePythonPaths <-
                    rewritePyvenvConfigExact
                      installRoot
                      candidateRoot
                      venvPath
                      venvDescriptor
                  requireNoRelocationResidual
                    candidateRoot
                    rootDescriptor
                    openedRootStatus
                    (oldRootBytes : sourcePythonPaths)
              )
            finalRootStatus <- Posix.getFdStatus rootDescriptor
            finalRootPathStatus <-
              Posix.getSymbolicLinkStatus candidateRoot
            unless
              ( stableExecutableStatus openedRootStatus finalRootStatus
                  && stableExecutableStatus
                    finalRootStatus
                    finalRootPathStatus
              )
              (ioError (userError "candidate relocation root changed during traversal"))
        )
        (closeFd rootDescriptor)

rewritePyvenvConfigExact ::
  FilePath ->
  FilePath ->
  FilePath ->
  Fd ->
  IO [ByteString.ByteString]
rewritePyvenvConfigExact
  installRoot
  candidateRoot
  venvPath
  venvDescriptor =
    mask $ \restore -> do
      descriptor <-
        openFdAt
          (Just venvDescriptor)
          "pyvenv.cfg"
          ReadWrite
          defaultFileFlags
            { nofollow = True,
              nonBlock = True,
              cloexec = True
            }
      finallyPreservingPrimary
        ( restore $ do
            openedStatus <- Posix.getFdStatus descriptor
            unless
              ( Posix.isRegularFile openedStatus
                  && fromIntegral (Posix.fileSize openedStatus)
                    <= maximumRelocationConfigBytes
              )
              (ioError (userError "pyvenv.cfg is not a bounded regular file"))
            contents <-
              readExactProvisioningDescriptorBytes
                descriptor
                (fromIntegral (Posix.fileSize openedStatus))
            text <-
              either
                (ioError . userError . ("pyvenv.cfg is not UTF-8: " <>) . show)
                pure
                (TextEncoding.decodeUtf8' contents)
            (rewritten, sourcePaths, candidateExecutable) <-
              either
                (ioError . userError)
                pure
                (rewritePyvenvConfig installRoot candidateRoot text)
            canonicalCandidateExecutable <-
              Directory.canonicalizePath candidateExecutable
            executableStatus <-
              Posix.getSymbolicLinkStatus canonicalCandidateExecutable
            unless
              ( writerPathWithin
                  (candidateRoot </> "python-home")
                  canonicalCandidateExecutable
                  && Posix.isRegularFile executableStatus
                  && Posix.fileMode executableStatus
                    .&. ( Posix.ownerExecuteMode
                            .|. Posix.groupExecuteMode
                            .|. Posix.otherExecuteMode
                        )
                    /= 0
              )
              (ioError (userError "pyvenv.cfg artifact-local executable is invalid"))
            let rewrittenBytes = TextEncoding.encodeUtf8 rewritten
            unless
              ( ByteString.length rewrittenBytes
                  <= fromIntegral maximumRelocationConfigBytes
              )
              (ioError (userError "rewritten pyvenv.cfg exceeds its fixed bound"))
            _ <- fdSeek descriptor AbsoluteSeek 0
            Posix.setFdSize descriptor 0
            writeProvisioningDescriptor descriptor rewrittenBytes
            fileSynchronise descriptor
            _ <- fdSeek descriptor AbsoluteSeek 0
            observed <-
              readExactProvisioningDescriptorBytes
                descriptor
                (fromIntegral (ByteString.length rewrittenBytes))
            finalStatus <- Posix.getFdStatus descriptor
            finalPathStatus <-
              Posix.getSymbolicLinkStatus (venvPath </> "pyvenv.cfg")
            reopenedStatus <-
              reopenFileEntryStatus venvDescriptor "pyvenv.cfg"
            unless
              ( observed == rewrittenBytes
                  && sameFileObject openedStatus finalStatus
                  && stableExecutableStatus finalStatus finalPathStatus
                  && stableExecutableStatus finalPathStatus reopenedStatus
              )
              (ioError (userError "rewritten pyvenv.cfg did not seal"))
            synchroniseProvisioningDirectory venvPath
            pure
              ( List.nub
                  [ TextEncoding.encodeUtf8 (Text.pack path)
                  | path <- sourcePaths,
                    normalise path
                      /= normalise candidateRoot,
                    normalise path
                      /= normalise installRoot
                  ]
              )
        )
        (closeFd descriptor)

rewritePyvenvConfig ::
  FilePath ->
  FilePath ->
  Text ->
  Either String (Text, [FilePath], FilePath)
rewritePyvenvConfig installRoot candidateRoot contents = do
  let sourceLines = Text.lines contents
      valuesFor key =
        [ Text.unpack value
        | line <- sourceLines,
          Just value <- [Text.stripPrefix (Text.pack (key <> " = ")) line]
        ]
      homeValues = valuesFor "home"
      executableValues = valuesFor "executable"
      commandValues = valuesFor "command"
  sourceHome <-
    requireSinglePyvenvValue "home" homeValues
  sourceExecutable <-
    requireSinglePyvenvValue "executable" executableValues
  _ <-
    requireSinglePyvenvValue "command" commandValues
  let executableLeaf = takeFileName sourceExecutable
      sourceFrameworkRoot = takeDirectory sourceHome
      sourceExecutableRoot =
        takeDirectory (takeDirectory sourceExecutable)
      finalHome = installRoot </> "python-home" </> "bin"
      finalExecutable = finalHome </> executableLeaf
      candidateExecutable =
        candidateRoot
          </> "python-home"
          </> "bin"
          </> executableLeaf
      finalCommand =
        finalExecutable
          <> " -m venv --copies "
          <> (installRoot </> "venv")
  unlessEither
    ( all
        validNormalizedAbsolutePath
        [ sourceHome,
          sourceExecutable,
          sourceFrameworkRoot,
          sourceExecutableRoot,
          installRoot,
          candidateRoot
        ]
        && validFixedPathComponent executableLeaf
        && writerPathWithin sourceFrameworkRoot sourceHome
        && writerPathWithin sourceExecutableRoot sourceExecutable
    )
    "pyvenv.cfg source or artifact path is invalid"
  let rewriteLine line
        | "home = " `Text.isPrefixOf` line =
            Text.pack ("home = " <> finalHome)
        | "executable = " `Text.isPrefixOf` line =
            Text.pack ("executable = " <> finalExecutable)
        | "command = " `Text.isPrefixOf` line =
            Text.pack ("command = " <> finalCommand)
        | otherwise = line
      rewritten = Text.unlines (map rewriteLine sourceLines)
  pure
    ( rewritten,
      [ sourceFrameworkRoot,
        sourceExecutableRoot,
        sourceHome,
        sourceExecutable
      ],
      candidateExecutable
    )

requireSinglePyvenvValue ::
  String ->
  [FilePath] ->
  Either String FilePath
requireSinglePyvenvValue label values =
  case values of
    [value] -> Right value
    _ -> Left ("pyvenv.cfg must contain exactly one " <> label <> " field")

requireNoRelocationResidual ::
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  [ByteString.ByteString] ->
  IO ()
requireNoRelocationResidual
  candidateRoot
  rootDescriptor
  rootStatus
  needles
    | null needles || any ByteString.null needles =
        ioError (userError "candidate relocation residual needle set is empty")
    | otherwise = do
        observed <-
          scanRelocatedCandidateDirectory
            candidateRoot
            rootDescriptor
            rootStatus
            0
            (List.nub needles)
            RelocatedCandidateScan
              { relocatedCandidateEntries = 0,
                relocatedCandidateBytes = 0,
                relocatedCandidateResidual = Nothing
              }
        case relocatedCandidateResidual observed of
          Nothing -> pure ()
          Just path ->
            ioError
              ( userError
                  ( "Apple engine candidate retained a forbidden source path: "
                      <> path
                  )
              )

withProvisioningDirectoryAt ::
  Fd ->
  FilePath ->
  FilePath ->
  (FilePath -> Fd -> Posix.FileStatus -> IO result) ->
  IO result
withProvisioningDirectoryAt
  parentDescriptor
  parentPath
  entry
  action =
    mask $ \restore -> do
      parentStatus <- Posix.getFdStatus parentDescriptor
      parentPathStatus <- Posix.getSymbolicLinkStatus parentPath
      unless
        (sameFileObject parentStatus parentPathStatus)
        (ioError (userError ("owned directory parent changed: " <> parentPath)))
      let path = parentPath </> entry
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
        ( restore $ do
            status <- Posix.getFdStatus descriptor
            pathStatus <- Posix.getSymbolicLinkStatus path
            unless
              ( Posix.isDirectory status
                  && not (Posix.isSymbolicLink pathStatus)
                  && stableExecutableStatus status pathStatus
              )
              (ioError (userError ("owned directory entry changed: " <> path)))
            result <- action path descriptor status
            finalStatus <- Posix.getFdStatus descriptor
            finalPathStatus <- Posix.getSymbolicLinkStatus path
            finalParentStatus <- Posix.getFdStatus parentDescriptor
            finalParentPathStatus <- Posix.getSymbolicLinkStatus parentPath
            unless
              ( stableExecutableStatus status finalStatus
                  && stableExecutableStatus finalStatus finalPathStatus
                  && sameFileObject parentStatus finalParentStatus
                  && sameFileObject
                    finalParentStatus
                    finalParentPathStatus
              )
              (ioError (userError ("owned directory changed during use: " <> path)))
            pure result
        )
        (closeFd descriptor)

rewriteRelocationEntry ::
  FilePath ->
  Fd ->
  Integer ->
  ByteString.ByteString ->
  ByteString.ByteString ->
  FilePath ->
  IO ()
rewriteRelocationEntry
  parentPath
  parentDescriptor
  maximumBytes
  oldRoot
  newRoot
  entry = do
    let path = parentPath </> entry
    fileResult <-
      try @IOException
        ( openFdAt
            (Just parentDescriptor)
            entry
            ReadWrite
            defaultFileFlags
              { nofollow = True,
                nonBlock = True,
                cloexec = True
              }
        )
    case fileResult of
      Right descriptor ->
        finallyPreservingPrimary
          ( rewriteRelocationDescriptor
              parentPath
              parentDescriptor
              path
              entry
              descriptor
              maximumBytes
              oldRoot
              newRoot
          )
          (closeFd descriptor)
      Left _ ->
        validateSkippedRelocationEntry
          parentPath
          parentDescriptor
          path
          entry

rewriteRelocationDescriptor ::
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  Integer ->
  ByteString.ByteString ->
  ByteString.ByteString ->
  IO ()
rewriteRelocationDescriptor
  parentPath
  parentDescriptor
  path
  entry
  descriptor
  maximumBytes
  oldRoot
  newRoot = do
    openedStatus <- Posix.getFdStatus descriptor
    unless
      ( Posix.isRegularFile openedStatus
          && fromIntegral (Posix.fileSize openedStatus)
            <= maximumBytes
      )
      (ioError (userError ("candidate relocation file exceeds its bound: " <> path)))
    contents <-
      readExactProvisioningDescriptorBytes
        descriptor
        (fromIntegral (Posix.fileSize openedStatus))
    stableStatus <- Posix.getFdStatus descriptor
    reopenedStatus <- reopenFileEntryStatus parentDescriptor entry
    unless
      ( stableExecutableStatus openedStatus stableStatus
          && stableExecutableStatus stableStatus reopenedStatus
      )
      (ioError (userError ("candidate relocation file changed before rewrite: " <> path)))
    let rewritten =
          replaceProvisioningBytes oldRoot newRoot contents
    when (rewritten /= contents) $ do
      _ <- fdSeek descriptor AbsoluteSeek 0
      Posix.setFdSize descriptor 0
      writeProvisioningDescriptor descriptor rewritten
      fileSynchronise descriptor
      _ <- fdSeek descriptor AbsoluteSeek 0
      observed <-
        readExactProvisioningDescriptorBytes
          descriptor
          (fromIntegral (ByteString.length rewritten))
      finalStatus <- Posix.getFdStatus descriptor
      finalPathStatus <- Posix.getSymbolicLinkStatus path
      parentStatus <- Posix.getFdStatus parentDescriptor
      parentPathStatus <- Posix.getSymbolicLinkStatus parentPath
      unless
        ( observed == rewritten
            && Posix.isRegularFile finalStatus
            && sameFileObject openedStatus finalStatus
            && sameFileObject finalStatus finalPathStatus
            && Posix.fileMode finalStatus .&. Posix.accessModes
              == Posix.fileMode openedStatus .&. Posix.accessModes
            && fromIntegral (Posix.fileSize finalStatus)
              == ByteString.length rewritten
            && sameFileObject parentStatus parentPathStatus
        )
        (ioError (userError ("candidate relocation rewrite did not seal: " <> path)))
      synchroniseProvisioningDirectory parentPath

replaceProvisioningBytes ::
  ByteString.ByteString ->
  ByteString.ByteString ->
  ByteString.ByteString ->
  ByteString.ByteString
replaceProvisioningBytes needle replacement input
  | ByteString.null needle = input
  | otherwise = go input []
  where
    go remaining pieces =
      let (prefix, suffix) =
            ByteString.breakSubstring needle remaining
       in if ByteString.null suffix
            then ByteString.concat (reverse (prefix : pieces))
            else
              go
                (ByteString.drop (ByteString.length needle) suffix)
                (replacement : prefix : pieces)

validateSkippedRelocationEntry ::
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  IO ()
validateSkippedRelocationEntry parentPath parentDescriptor path entry = do
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
    Right descriptor ->
      finallyPreservingPrimary
        ( do
            status <- Posix.getFdStatus descriptor
            pathStatus <- Posix.getSymbolicLinkStatus path
            unless
              ( Posix.isDirectory status
                  && stableExecutableStatus status pathStatus
              )
              (ioError (userError ("candidate relocation directory changed: " <> path)))
        )
        (closeFd descriptor)
    Left _ -> do
      _ <-
        validateStableProvisioningSymlink
          parentPath
          parentDescriptor
          path
      pure ()

data RelocatedCandidateScan = RelocatedCandidateScan
  { relocatedCandidateEntries :: !Integer,
    relocatedCandidateBytes :: !Integer,
    relocatedCandidateResidual :: !(Maybe FilePath)
  }

scanRelocatedCandidateDirectory ::
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  Int ->
  [ByteString.ByteString] ->
  RelocatedCandidateScan ->
  IO RelocatedCandidateScan
scanRelocatedCandidateDirectory
  path
  descriptor
  listedStatus
  depth
  needles
  state = do
    unless
      ( depth <= maximumRelocationCandidateDepth
          && relocatedCandidateEntries state
            <= maximumRelocationCandidateEntries
      )
      (ioError (userError "candidate residual traversal exceeds its fixed bound"))
    entries <-
      listDirectoryBoundedFromDescriptor
        descriptor
        ( maximumRelocationCandidateEntries
            - relocatedCandidateEntries state
        )
    observed <-
      foldM
        (scanRelocatedCandidateEntry path descriptor depth needles)
        state
        entries
    finalStatus <- Posix.getFdStatus descriptor
    unless
      (stableExecutableStatus listedStatus finalStatus)
      (ioError (userError ("candidate residual directory changed: " <> path)))
    pure observed

scanRelocatedCandidateEntry ::
  FilePath ->
  Fd ->
  Int ->
  [ByteString.ByteString] ->
  RelocatedCandidateScan ->
  FilePath ->
  IO RelocatedCandidateScan
scanRelocatedCandidateEntry
  parentPath
  parentDescriptor
  depth
  needles
  state
  entry = do
    let path = parentPath </> entry
        countedState =
          state
            { relocatedCandidateEntries =
                relocatedCandidateEntries state + 1
            }
    requireRelocatedCandidateBound countedState
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
              status <- Posix.getFdStatus childDescriptor
              observed <-
                scanRelocatedCandidateDirectory
                  path
                  childDescriptor
                  status
                  (depth + 1)
                  needles
                  countedState
              finalStatus <- Posix.getFdStatus childDescriptor
              reopenedStatus <-
                reopenDirectoryEntryStatus parentDescriptor entry
              unless
                ( stableExecutableStatus status finalStatus
                    && stableExecutableStatus
                      finalStatus
                      reopenedStatus
                )
                (ioError (userError ("candidate residual directory changed: " <> path)))
              pure observed
          )
          (closeFd childDescriptor)
      Left _ ->
        scanRelocatedCandidateFile
          parentPath
          parentDescriptor
          entry
          path
          needles
          countedState

scanRelocatedCandidateFile ::
  FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  [ByteString.ByteString] ->
  RelocatedCandidateScan ->
  IO RelocatedCandidateScan
scanRelocatedCandidateFile
  parentPath
  parentDescriptor
  entry
  path
  needles
  state = do
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
              status <- Posix.getFdStatus descriptor
              unless
                (Posix.isRegularFile status)
                (ioError (userError ("candidate residual entry is unsupported: " <> path)))
              interpreted <-
                relocationFileInterpretsPaths
                  path
                  descriptor
                  (fromIntegral (Posix.fileSize status))
              let scannedBytes
                    | interpreted =
                        fromIntegral (Posix.fileSize status)
                    | otherwise = 0
                  nextState =
                    state
                      { relocatedCandidateBytes =
                          relocatedCandidateBytes state
                            + scannedBytes
                      }
              requireRelocatedCandidateBound nextState
              contains <-
                if interpreted
                  then
                    descriptorContainsAnyProvisioningBytes
                      descriptor
                      (fromIntegral (Posix.fileSize status))
                      needles
                  else pure False
              finalStatus <- Posix.getFdStatus descriptor
              reopenedStatus <-
                reopenFileEntryStatus parentDescriptor entry
              unless
                ( stableExecutableStatus status finalStatus
                    && stableExecutableStatus
                      finalStatus
                      reopenedStatus
                )
                (ioError (userError ("candidate residual file changed: " <> path)))
              pure
                ( if contains
                    then
                      nextState
                        { relocatedCandidateResidual =
                            case relocatedCandidateResidual nextState of
                              Nothing -> Just path
                              existing -> existing
                        }
                    else nextState
                )
          )
          (closeFd descriptor)
      Left _ -> do
        target <-
          validateStableProvisioningSymlink
            parentPath
            parentDescriptor
            path
        let nextState =
              state
                { relocatedCandidateBytes =
                    relocatedCandidateBytes state
                      + fromIntegral (ByteString.length target)
                }
        requireRelocatedCandidateBound nextState
        pure
          ( if any (`ByteString.isInfixOf` target) needles
              then
                nextState
                  { relocatedCandidateResidual =
                      case relocatedCandidateResidual nextState of
                        Nothing -> Just path
                        existing -> existing
                  }
              else nextState
          )

relocationFileInterpretsPaths ::
  FilePath ->
  Fd ->
  Integer ->
  IO Bool
relocationFileInterpretsPaths path descriptor expectedBytes = do
  shebang <- descriptorHasShebang descriptor expectedBytes
  pure
    ( shebang
        || takeFileName path == "pyvenv.cfg"
        || takeFileName path == "apple_native_runner.py"
        || "activate" `List.isPrefixOf` takeFileName path
        || takeExtension path
          `elem` [".pth", ".cfg", ".ini", ".toml"]
    )

descriptorHasShebang :: Fd -> Integer -> IO Bool
descriptorHasShebang descriptor expectedBytes
  | expectedBytes < 2 = pure False
  | otherwise = do
      _ <- fdSeek descriptor AbsoluteSeek 0
      prefix <- PosixByteString.fdRead descriptor 2
      _ <- fdSeek descriptor AbsoluteSeek 0
      pure (prefix == ByteString.pack [35, 33])

descriptorContainsAnyProvisioningBytes ::
  Fd ->
  Integer ->
  [ByteString.ByteString] ->
  IO Bool
descriptorContainsAnyProvisioningBytes _ _ [] =
  pure False
descriptorContainsAnyProvisioningBytes descriptor expectedBytes (needle : remaining) = do
  _ <- fdSeek descriptor AbsoluteSeek 0
  contains <-
    descriptorContainsProvisioningBytes
      descriptor
      expectedBytes
      needle
  if contains
    then pure True
    else
      descriptorContainsAnyProvisioningBytes
        descriptor
        expectedBytes
        remaining

validateStableProvisioningSymlink ::
  FilePath ->
  Fd ->
  FilePath ->
  IO ByteString.ByteString
validateStableProvisioningSymlink parentPath parentDescriptor path = do
  parentStatus <- Posix.getFdStatus parentDescriptor
  parentPathStatus <- Posix.getSymbolicLinkStatus parentPath
  status <- Posix.getSymbolicLinkStatus path
  unless
    (Posix.isSymbolicLink status)
    (ioError (userError ("provisioning entry is neither openable nor a symlink: " <> path)))
  target <- Posix.readSymbolicLink path
  finalStatus <- Posix.getSymbolicLinkStatus path
  finalTarget <- Posix.readSymbolicLink path
  finalParentStatus <- Posix.getFdStatus parentDescriptor
  finalParentPathStatus <- Posix.getSymbolicLinkStatus parentPath
  unless
    ( stableExecutableStatus status finalStatus
        && target == finalTarget
        && sameFileObject parentStatus parentPathStatus
        && sameFileObject parentStatus finalParentStatus
        && sameFileObject
          finalParentStatus
          finalParentPathStatus
    )
    (ioError (userError ("provisioning symlink changed: " <> path)))
  pure (TextEncoding.encodeUtf8 (Text.pack target))

requireRelocatedCandidateBound ::
  RelocatedCandidateScan ->
  IO ()
requireRelocatedCandidateBound state =
  unless
    ( relocatedCandidateEntries state >= 0
        && relocatedCandidateEntries state
          <= maximumRelocationCandidateEntries
        && relocatedCandidateBytes state >= 0
        && relocatedCandidateBytes state
          <= maximumRelocationCandidateBytes
    )
    (ioError (userError "candidate residual traversal exceeds its global bound"))

descriptorContainsProvisioningBytes ::
  Fd ->
  Integer ->
  ByteString.ByteString ->
  IO Bool
descriptorContainsProvisioningBytes descriptor expectedBytes needle
  | ByteString.null needle =
      ioError (userError "candidate residual needle must not be empty")
  | otherwise =
      go 0 ByteString.empty False
  where
    overlapBytes = ByteString.length needle - 1

    go observedBytes carry found
      | observedBytes > expectedBytes =
          ioError (userError "candidate residual descriptor exceeded its exact byte bound")
      | otherwise = do
          let remaining = expectedBytes - observedBytes
              requested =
                fromIntegral (min (64 * 1024) (remaining + 1))
          chunk <- PosixByteString.fdRead descriptor requested
          if ByteString.null chunk
            then do
              unless
                (observedBytes == expectedBytes)
                (ioError (userError "candidate residual descriptor ended early"))
              pure found
            else do
              let nextObserved =
                    observedBytes
                      + fromIntegral (ByteString.length chunk)
              unless
                (nextObserved <= expectedBytes)
                (ioError (userError "candidate residual descriptor grew during scan"))
              let combined = carry <> chunk
                  nextFound =
                    found || ByteString.isInfixOf needle combined
                  nextCarry =
                    ByteString.drop
                      (max 0 (ByteString.length combined - overlapBytes))
                      combined
              go nextObserved nextCarry nextFound

provisioningWriteFile ::
  EngineWriter w s q ->
  FilePath ->
  String ->
  ProvisioningSession s ()
provisioningWriteFile (EngineWriter _ _ authorizedRoot) path contents =
  ProvisioningSession $ do
    authorizedPath <-
      authorizedWriterPath "engine text write" authorizedRoot path
    writeFile authorizedPath contents
    validateWriterRootIdentity "engine text write" authorizedRoot

provisioningProjectWriteFile ::
  ProjectWriter p s q ->
  FilePath ->
  String ->
  ProvisioningSession s ()
provisioningProjectWriteFile (ProjectWriter _ authorizedRoot) path contents =
  ProvisioningSession $ do
    authorizedPath <-
      authorizedWriterPath "project text write" authorizedRoot path
    writeFile authorizedPath contents
    validateWriterRootIdentity "project text write" authorizedRoot

provisioningWriteBytes ::
  EngineWriter w s q ->
  FilePath ->
  ByteString.ByteString ->
  ProvisioningSession s ()
provisioningWriteBytes (EngineWriter _ _ authorizedRoot) path contents =
  ProvisioningSession $ do
    authorizedPath <-
      authorizedWriterPath "engine byte write" authorizedRoot path
    ByteString.writeFile authorizedPath contents
    validateWriterRootIdentity "engine byte write" authorizedRoot

data ProvisioningPathKind
  = ProvisioningDirectory
  | ProvisioningRegularFile
  | ProvisioningSymbolicLink
  | ProvisioningSpecialFile
  deriving (Eq, Show)

data ProvisioningPathInfo = ProvisioningPathInfo
  { provisioningPathKind :: !ProvisioningPathKind,
    provisioningPathFileSize :: !FileOffset,
    provisioningPathDeviceId :: !DeviceID,
    provisioningPathFileId :: !FileID
  }
  deriving (Eq, Show)

provisioningPathInfo :: FilePath -> ProvisioningSession s ProvisioningPathInfo
provisioningPathInfo path =
  ProvisioningSession $ do
    status <- Posix.getSymbolicLinkStatus path
    pure (pathInfoFromStatus status)

pathInfoFromStatus :: Posix.FileStatus -> ProvisioningPathInfo
pathInfoFromStatus status =
  ProvisioningPathInfo
    { provisioningPathKind =
        if
          | Posix.isSymbolicLink status -> ProvisioningSymbolicLink
          | Posix.isDirectory status -> ProvisioningDirectory
          | Posix.isRegularFile status -> ProvisioningRegularFile
          | otherwise -> ProvisioningSpecialFile,
      provisioningPathFileSize = Posix.fileSize status,
      provisioningPathDeviceId = Posix.deviceID status,
      provisioningPathFileId = Posix.fileID status
    }

newtype DurableProvisioningRecord s
  = DurableProvisioningRecord FilePath

type role DurableProvisioningRecord nominal

maximumDurableProvisioningRecordBytes :: Int
maximumDurableProvisioningRecordBytes = 16384

provisioningPublishDurableRecord ::
  EngineWriter w s q ->
  FilePath ->
  ByteString.ByteString ->
  ProvisioningSession s (DurableProvisioningRecord s)
provisioningPublishDurableRecord
  (EngineWriter _ _ authorizedRoot)
  path
  contents =
    ProvisioningSession $ do
      authorizedPath <-
        authorizedWriterPath "durable record publication" authorizedRoot path
      validateDurableRecordPayload authorizedPath contents
      reconcileDurableRecordStaging authorizedPath
      existing <- try @IOException (Posix.getSymbolicLinkStatus authorizedPath)
      case existing of
        Right _ ->
          ioError
            (userError ("durable provisioning record already exists: " <> authorizedPath))
        Left failure
          | isDoesNotExistError failure ->
              publishDurableRecordBytes False authorizedPath contents
          | otherwise -> ioError failure
      validateWriterRootIdentity "durable record publication" authorizedRoot
      pure (DurableProvisioningRecord authorizedPath)

provisioningRecoverDurableRecord ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession
    s
    (Maybe (ByteString.ByteString, DurableProvisioningRecord s))
provisioningRecoverDurableRecord
  (EngineWriter _ _ authorizedRoot)
  path =
    ProvisioningSession $ do
      authorizedPath <-
        authorizedWriterPath "durable record recovery" authorizedRoot path
      reconcileDurableRecordStaging authorizedPath
      statusResult <-
        try @IOException (Posix.getSymbolicLinkStatus authorizedPath)
      case statusResult of
        Left failure
          | isDoesNotExistError failure -> pure Nothing
          | otherwise -> ioError failure
        Right status
          | Posix.isRegularFile status
              && not (Posix.isSymbolicLink status) -> do
              contents <-
                readRegularFileNoFollowBounded
                  authorizedPath
                  maximumDurableProvisioningRecordBytes
              pure
                (Just (contents, DurableProvisioningRecord authorizedPath))
          | otherwise ->
              ioError
                ( userError
                    ( "durable provisioning record is not a regular file: "
                        <> authorizedPath
                    )
                )

provisioningReplaceDurableRecord ::
  EngineWriter w s q ->
  DurableProvisioningRecord s ->
  ByteString.ByteString ->
  ProvisioningSession s (DurableProvisioningRecord s)
provisioningReplaceDurableRecord
  (EngineWriter _ _ authorizedRoot)
  (DurableProvisioningRecord path)
  contents =
    ProvisioningSession $ do
      authorizedPath <-
        authorizedWriterPath "durable record replacement" authorizedRoot path
      validateDurableRecordPayload authorizedPath contents
      requireDurableRecordPath authorizedPath
      reconcileDurableRecordStaging authorizedPath
      publishDurableRecordBytes True authorizedPath contents
      validateWriterRootIdentity "durable record replacement" authorizedRoot
      pure (DurableProvisioningRecord authorizedPath)

provisioningRetireDurableRecord ::
  EngineWriter w s q ->
  DurableProvisioningRecord s ->
  ProvisioningSession s ()
provisioningRetireDurableRecord
  (EngineWriter _ _ authorizedRoot)
  (DurableProvisioningRecord path) =
    ProvisioningSession $ do
      authorizedPath <-
        authorizedWriterPath "durable record retirement" authorizedRoot path
      requireDurableRecordPath authorizedPath
      Directory.removeFile authorizedPath
      synchroniseProvisioningDirectory (takeDirectory authorizedPath)
      reconcileDurableRecordStaging authorizedPath
      validateWriterRootIdentity "durable record retirement" authorizedRoot

provisioningReadBoundedNoFollow ::
  FilePath ->
  Int ->
  ProvisioningSession s ByteString.ByteString
provisioningReadBoundedNoFollow path maximumBytes
  | maximumBytes <= 0 || maximumBytes > 1024 * 1024 =
      failProvisioningSession
        "bounded nofollow read requires a limit between 1 and 1048576 bytes"
  | otherwise =
      ProvisioningSession
        (readRegularFileNoFollowBounded path maximumBytes)

validateDurableRecordPayload ::
  FilePath ->
  ByteString.ByteString ->
  IO ()
validateDurableRecordPayload path contents =
  unless
    ( isAbsolute path
        && not (ByteString.null contents)
        && ByteString.length contents
          <= maximumDurableProvisioningRecordBytes
    )
    (ioError (userError "durable provisioning record path or payload is invalid"))

durableRecordStagingPath :: FilePath -> FilePath
durableRecordStagingPath path = path <> ".incoming"

reconcileDurableRecordStaging :: FilePath -> IO ()
reconcileDurableRecordStaging path = do
  let stagingPath = durableRecordStagingPath path
  statusResult <-
    try @IOException (Posix.getSymbolicLinkStatus stagingPath)
  case statusResult of
    Left failure
      | isDoesNotExistError failure -> pure ()
      | otherwise -> ioError failure
    Right status
      | Posix.isRegularFile status
          && not (Posix.isSymbolicLink status) -> do
          Directory.removeFile stagingPath
          synchroniseProvisioningDirectory (takeDirectory path)
      | otherwise ->
          ioError
            (userError ("durable record staging path is unsafe: " <> stagingPath))

publishDurableRecordBytes ::
  Bool ->
  FilePath ->
  ByteString.ByteString ->
  IO ()
publishDurableRecordBytes replacing path contents =
  mask $ \restore -> do
    let stagingPath = durableRecordStagingPath path
        recordMode =
          Posix.ownerReadMode .|. Posix.ownerWriteMode
    descriptor <-
      openFd
        stagingPath
        WriteOnly
        defaultFileFlags
          { exclusive = True,
            nofollow = True,
            creat = Just recordMode,
            cloexec = True
          }
    onExceptionPreservingPrimary
      ( do
          finallyPreservingPrimary
            ( restore $ do
                writeProvisioningDescriptor descriptor contents
                fileSynchronise descriptor
            )
            (closeFd descriptor)
          when replacing (requireDurableRecordPath path)
          Directory.renameFile stagingPath path
          synchroniseProvisioningDirectory (takeDirectory path)
      )
      ( do
          _ <- try @IOException (closeFd descriptor)
          _ <- try @IOException (Directory.removeFile stagingPath)
          synchroniseProvisioningDirectory (takeDirectory path)
      )

requireDurableRecordPath :: FilePath -> IO ()
requireDurableRecordPath path = do
  status <- Posix.getSymbolicLinkStatus path
  unless
    (Posix.isRegularFile status && not (Posix.isSymbolicLink status))
    (ioError (userError ("durable provisioning record is unsafe: " <> path)))

readRegularFileNoFollowBounded ::
  FilePath ->
  Int ->
  IO ByteString.ByteString
readRegularFileNoFollowBounded path maximumBytes =
  mask $ \restore -> do
    listedStatus <- Posix.getSymbolicLinkStatus path
    unless
      ( Posix.isRegularFile listedStatus
          && not (Posix.isSymbolicLink listedStatus)
          && Posix.fileSize listedStatus <= fromIntegral maximumBytes
      )
      (ioError (userError ("bounded nofollow file is invalid: " <> path)))
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
          openedStatus <- Posix.getFdStatus descriptor
          unless
            (stableExecutableStatus listedStatus openedStatus)
            (ioError (userError ("bounded nofollow file changed before open: " <> path)))
          contents <-
            readProvisioningDescriptorBounded
              descriptor
              maximumBytes
              0
              []
          finalStatus <- Posix.getFdStatus descriptor
          finalPathStatus <- Posix.getSymbolicLinkStatus path
          unless
            ( ByteString.length contents
                == fromIntegral (Posix.fileSize listedStatus)
                && stableExecutableStatus openedStatus finalStatus
                && stableExecutableStatus finalStatus finalPathStatus
            )
            (ioError (userError ("bounded nofollow file changed while reading: " <> path)))
          pure contents
      )
      (closeFd descriptor)

readProvisioningDescriptorBounded ::
  Fd ->
  Int ->
  Int ->
  [ByteString.ByteString] ->
  IO ByteString.ByteString
readProvisioningDescriptorBounded descriptor maximumBytes bytesRead chunks = do
  chunk <-
    PosixByteString.fdRead
      descriptor
      (fromIntegral (maximumBytes + 1 - bytesRead))
  if ByteString.null chunk
    then pure (ByteString.concat (reverse chunks))
    else do
      let nextBytes = bytesRead + ByteString.length chunk
      unless
        (nextBytes <= maximumBytes)
        (ioError (userError "bounded nofollow file exceeded its limit"))
      readProvisioningDescriptorBounded
        descriptor
        maximumBytes
        nextBytes
        (chunk : chunks)

synchroniseProvisioningDirectory :: FilePath -> IO ()
synchroniseProvisioningDirectory path =
  mask $ \restore -> do
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
          status <- Posix.getFdStatus descriptor
          unless
            (Posix.isDirectory status)
            (ioError (userError ("fsync path is not a directory: " <> path)))
          fileSynchronise descriptor
      )
      (closeFd descriptor)

synchroniseProvisioningFile :: FilePath -> IO ()
synchroniseProvisioningFile path =
  mask $ \restore -> do
    descriptor <-
      openFd
        path
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    finallyPreservingPrimary
      (restore (fileSynchronise descriptor))
      (closeFd descriptor)

data ProvisioningProcessIdentity s = ProvisioningProcessIdentity
  { provisioningProcessIdentityPid :: !Integer,
    provisioningProcessIdentityBirth :: !Text
  }

type role ProvisioningProcessIdentity nominal

provisioningCurrentProcessIdentity ::
  ProvisioningSession s (ProvisioningProcessIdentity s)
provisioningCurrentProcessIdentity =
  ProvisioningSession $ do
    processId <- fromIntegral <$> getProcessID
    birthIdentity <- registerCurrentProcessIdentity
    pure
      ProvisioningProcessIdentity
        { provisioningProcessIdentityPid = processId,
          provisioningProcessIdentityBirth =
            Text.pack (renderProcessBirthIdentity birthIdentity)
        }

provisioningExactProcessIdentityAbsent ::
  Integer ->
  Text ->
  ProvisioningSession s (Either String Bool)
provisioningExactProcessIdentityAbsent processId renderedBirth =
  ProvisioningSession $
    case parseProcessBirthIdentity (Text.unpack renderedBirth) of
      Nothing ->
        pure (Left "recorded provisioning process birth identity is invalid")
      Just expected
        | processId <= 0 || processId > 2147483647 ->
            pure (Left "recorded provisioning process id is invalid")
        | otherwise -> do
            current <- readProcessBirthIdentity processId
            pure (Right (current /= Just expected))

provisioningFileExecutable :: FilePath -> ProvisioningSession s Bool
provisioningFileExecutable path =
  ProvisioningSession
    (Directory.executable <$> Directory.getPermissions path)

provisioningMakeExecutable ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningMakeExecutable (EngineWriter _ _ authorizedRoot) path =
  ProvisioningSession $ do
    authorizedPath <-
      authorizedWriterPath "engine executable mutation" authorizedRoot path
    permissions <- Directory.getPermissions authorizedPath
    Directory.setPermissions
      authorizedPath
      (Directory.setOwnerExecutable True permissions)
    validateWriterRootIdentity "engine executable mutation" authorizedRoot

provisioningReconcileArtifactRoot ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningReconcileArtifactRoot
  (EngineWriter authority _recovered authorizedRoot)
  installRoot =
    ProvisioningSession $ do
      authorizedInstallRoot <-
        authorizedWriterPath
          "artifact reconciliation"
          authorizedRoot
          installRoot
      ArtifactInternal.reconcileEngineArtifactRoot
        authority
        authorizedInstallRoot
      validateWriterRootIdentity "artifact reconciliation" authorizedRoot

-- | Acquire, use, and release a provisioning resource without an asynchronous
-- gap after acquisition. Primary and cleanup diagnostics are both preserved.
bracketProvisioning ::
  ProvisioningSession s resource ->
  (resource -> ProvisioningSession s cleanup) ->
  (resource -> ProvisioningSession s result) ->
  ProvisioningSession s result
bracketProvisioning
  (ProvisioningSession acquire)
  release
  useResource =
    ProvisioningSession
      ( bracketPreservingPrimary
          acquire
          (runSession . release)
          (runSession . useResource)
      )
    where
      runSession (ProvisioningSession action) = action

installPoetryProject ::
  ProjectWriter p s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedPoetry s ->
  ProvisioningSession s ProvisioningOutcome
installPoetryProject writer grant deadline poetry =
  installPoetryProjectWithGroups
    writer
    grant
    deadline
    poetry
    []

installPoetryProjectWithGroups ::
  ProjectWriter p s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedPoetry s ->
  [PoetryInstallGroup] ->
  ProvisioningSession s ProvisioningOutcome
installPoetryProjectWithGroups
  (ProjectWriter _ projectRoot)
  grant
  deadline
  (ResolvedPoetry (identity, closureIdentities, runtimeLibraries))
  groups =
    runProvisioningCommandWithExecutableInWriter
      projectRoot
      []
      grant
      deadline
      identity
      closureIdentities
      runtimeLibraries
      ( Internal.InstallPoetryProject
          (authorizedWriterCanonicalRoot projectRoot)
          [group | PoetryInstallGroup group <- List.nub groups]
      )

generatePythonProtoBindings ::
  ProjectWriter p s q ->
  GeneratedBindingsWriter g s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedProjectPython s ->
  ProvisioningSession s ProvisioningOutcome
generatePythonProtoBindings
  (ProjectWriter _ projectRoot)
  (GeneratedBindingsWriter _ repositoryRoot _outputRoot)
  grant
  deadline
  (ResolvedProjectPython (identity, closureIdentities, runtimeLibraries)) =
    runProvisioningCommandWithExecutableInWriter
      repositoryRoot
      []
      grant
      deadline
      identity
      closureIdentities
      runtimeLibraries
      ( Internal.GeneratePythonProto
          (authorizedWriterCanonicalRoot projectRoot)
          (authorizedWriterCanonicalRoot repositoryRoot)
      )

probePythonVersion ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedPython s ->
  FilePath ->
  ProvisioningSession s ProvisioningOutcome
probePythonVersion
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  (ResolvedPython (adapter, identity))
  workingDirectory = do
    authorizedWorkingDirectory <-
      ProvisioningSession
        ( authorizedWriterPath
            "Python version probe working directory"
            engineRoot
            workingDirectory
        )
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Python version probe working directory"
            engineRoot
            authorizedWorkingDirectory
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      identity
      []
      []
      ( Internal.ProbePythonVersion
          adapter
          authorizedWorkingDirectory
      )

probePoetryBootstrapPython ::
  PoetryBootstrapWriter b s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedPython s ->
  ProvisioningSession s ProvisioningOutcome
probePoetryBootstrapPython
  (PoetryBootstrapWriter _ homeRoot poetryHome)
  grant
  deadline
  (ResolvedPython (adapter, identity)) = do
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Poetry bootstrap Python probe"
            homeRoot
            poetryHome
        )
    runProvisioningCommandWithExecutableInWriter
      homeRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.ProbePythonVersion adapter poetryHome)

createPythonVenv ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedPython s ->
  FilePath ->
  ProvisioningSession s ProvisioningOutcome
createPythonVenv
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  (ResolvedPython (adapter, identity))
  artifactRoot = do
    authorizedArtifactRoot <-
      ProvisioningSession
        (authorizedWriterPath "Python venv root" engineRoot artifactRoot)
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Python venv root"
            engineRoot
            authorizedArtifactRoot
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.CreatePythonVenv adapter authorizedArtifactRoot)

materializeCandidatePythonTarget ::
  EngineWriter w s q ->
  ResolvedPython s ->
  FilePath ->
  ProvisioningSession s (CandidatePythonTarget s)
materializeCandidatePythonTarget
  (EngineWriter _ _ engineRoot)
  (ResolvedPython (adapter, hostIdentity))
  artifactRoot =
    ProvisioningSession $ do
      authorizedArtifactRoot <-
        authorizedWriterPath
          "candidate Python target root"
          engineRoot
          artifactRoot
      targetIdentity <-
        materializeFixedVenvPython
          "candidate Python target"
          engineRoot
          authorizedArtifactRoot
          hostIdentity
      validateWriterRootIdentity
        "candidate Python target"
        engineRoot
      pure
        CandidatePythonTarget
          { candidatePythonTargetInternalAdapter = adapter,
            candidatePythonTargetRoot = authorizedArtifactRoot,
            candidatePythonTargetIdentity = targetIdentity
          }

materializeFixedVenvPython ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  ResolvedExecutableIdentity ->
  IO ResolvedExecutableIdentity
materializeFixedVenvPython label authorizedRoot venvOwnerRoot hostIdentity = do
  let configuredVenvPython =
        venvOwnerRoot </> "venv" </> "bin" </> "python"
      installedTarget =
        venvOwnerRoot </> Internal.fixedVenvPythonRelativePath
  venvIdentity <- resolveExactExecutableIdentity configuredVenvPython
  unless
    ( executablePayloadMatches hostIdentity venvIdentity
        && writerPathWithin venvOwnerRoot installedTarget
    )
    (ioError (userError (label <> " disagrees with its resolved host interpreter")))
  targetComponents <-
    authorizedWriterRelativeComponents
      label
      authorizedRoot
      installedTarget
  existing <-
    observeAuthorizedPathStatus
      label
      authorizedRoot
      installedTarget
  case existing of
    Nothing -> pure ()
    Just status
      | Posix.isRegularFile status ->
          runAuthorizedFilesystemMutation
            (label <> " reset")
            authorizedRoot
            ( Subprocess.provisioningRemoveTreeLeaf
                (authorizedWriterMutationRoot authorizedRoot)
                (init targetComponents)
                (last targetComponents)
            )
      | otherwise ->
          ioError (userError (label <> " is not a regular file"))
  _ <-
    copyRegularFileStable
      maximumExactRuntimeFileBytes
      (resolvedExecutableCanonicalPath venvIdentity)
      installedTarget
  targetIdentity <- resolveExactExecutableIdentity installedTarget
  unless
    ( normalise (resolvedExecutableCanonicalPath targetIdentity)
        == normalise installedTarget
        && writerPathWithin
          venvOwnerRoot
          (resolvedExecutableCanonicalPath targetIdentity)
        && executablePayloadMatches venvIdentity targetIdentity
        && executableIdentityHasExecuteBit targetIdentity
    )
    (ioError (userError (label <> " is not an exact owned regular executable")))
  pure targetIdentity

executablePayloadMatches ::
  ResolvedExecutableIdentity ->
  ResolvedExecutableIdentity ->
  Bool
executablePayloadMatches expected observed =
  Posix.fileSize (resolvedExecutableCanonicalStatus expected)
    == Posix.fileSize (resolvedExecutableCanonicalStatus observed)
    && executableIdentityHasExecuteBit expected
    && executableIdentityHasExecuteBit observed
    && resolvedExecutableDigest expected
      == resolvedExecutableDigest observed

requireCandidatePythonTarget ::
  Internal.ApplePythonAdapterId ->
  FilePath ->
  CandidatePythonTarget s ->
  ProvisioningSession s ResolvedExecutableIdentity
requireCandidatePythonTarget
  expectedAdapter
  expectedRoot
  target
    | candidatePythonTargetInternalAdapter target /= expectedAdapter =
        failProvisioningSession "candidate Python target belongs to another adapter"
    | normalise (candidatePythonTargetRoot target)
        /= normalise expectedRoot =
        failProvisioningSession "candidate Python target belongs to another artifact root"
    | otherwise = do
        let identity = candidatePythonTargetIdentity target
            expectedPath =
              normalise expectedRoot
                </> Internal.installedSmokeExecutableRelativePath
                  (Internal.appleAdapterForPython expectedAdapter)
        validation <-
          ProvisioningSession (revalidateExecutableIdentity identity)
        case validation of
          Left failure ->
            failProvisioningSession
              ("candidate Python target changed: " <> failure)
          Right ()
            | normalise (resolvedExecutableCanonicalPath identity)
                == normalise expectedPath ->
                pure identity
            | otherwise ->
                failProvisioningSession
                  "candidate Python target escaped its fixed artifact path"

createPoetryBootstrapVenv ::
  PoetryBootstrapWriter b s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedPython s ->
  ProvisioningSession s ProvisioningOutcome
createPoetryBootstrapVenv
  (PoetryBootstrapWriter _ homeRoot poetryHome)
  grant
  deadline
  (ResolvedPython (adapter, identity)) = do
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Poetry bootstrap venv"
            homeRoot
            poetryHome
        )
    runProvisioningCommandWithExecutableInWriter
      homeRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.CreatePythonVenv adapter poetryHome)

materializePoetryBootstrapPython ::
  PoetryBootstrapWriter b s q ->
  ResolvedPython s ->
  ProvisioningSession s (PoetryBootstrapPython s)
materializePoetryBootstrapPython
  (PoetryBootstrapWriter _ homeRoot poetryHome)
  (ResolvedPython (_, hostIdentity)) =
    ProvisioningSession $ do
      identity <-
        materializeFixedVenvPython
          "Poetry bootstrap Python target"
          homeRoot
          poetryHome
          hostIdentity
      validateWriterRootIdentity
        "Poetry bootstrap Python target"
        homeRoot
      pure
        PoetryBootstrapPython
          { poetryBootstrapPythonRoot = poetryHome,
            poetryBootstrapPythonIdentity = identity
          }

installPinnedPoetryBootstrap ::
  PoetryBootstrapWriter b s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  PoetryBootstrapPython s ->
  ProvisioningSession s ProvisioningOutcome
installPinnedPoetryBootstrap
  (PoetryBootstrapWriter _ homeRoot poetryHome)
  grant
  deadline
  (PoetryBootstrapPython targetRoot identity) = do
    unless
      ( normalise targetRoot == normalise poetryHome
          && normalise (resolvedExecutableCanonicalPath identity)
            == normalise (poetryHome </> Internal.fixedVenvPythonRelativePath)
      )
      (failProvisioningSession "Poetry bootstrap Python belongs to another home")
    validation <-
      ProvisioningSession (revalidateExecutableIdentity identity)
    case validation of
      Left failure ->
        failProvisioningSession
          ("Poetry bootstrap Python changed: " <> failure)
      Right () -> pure ()
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Poetry bootstrap installation"
            homeRoot
            poetryHome
        )
    runProvisioningCommandWithExecutableInWriter
      homeRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.InstallPoetryBootstrap poetryHome)

upgradePinnedPip ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  CandidatePythonTarget s ->
  ProvisioningSession s ProvisioningOutcome
upgradePinnedPip
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  target = do
    let adapter = candidatePythonTargetInternalAdapter target
        artifactRoot = candidatePythonTargetRoot target
    identity <-
      requireCandidatePythonTarget adapter artifactRoot target
    authorizedArtifactRoot <-
      ProvisioningSession
        (authorizedWriterPath "pip upgrade artifact root" engineRoot artifactRoot)
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "pip upgrade artifact root"
            engineRoot
            authorizedArtifactRoot
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.UpgradePinnedPip adapter authorizedArtifactRoot)

installPinnedRequirements ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  CandidatePythonTarget s ->
  ProvisioningSession s ProvisioningOutcome
installPinnedRequirements
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  target = do
    let adapter = candidatePythonTargetInternalAdapter target
        artifactRoot = candidatePythonTargetRoot target
    identity <-
      requireCandidatePythonTarget adapter artifactRoot target
    authorizedArtifactRoot <-
      ProvisioningSession
        ( authorizedWriterPath
            "requirements install artifact root"
            engineRoot
            artifactRoot
        )
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "requirements install artifact root"
            engineRoot
            authorizedArtifactRoot
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.InstallPinnedRequirements adapter authorizedArtifactRoot)

downloadAudiverisDmg ::
  DownloadCacheWriter d s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ProvisioningSession s ProvisioningOutcome
downloadAudiverisDmg
  (DownloadCacheWriter _ cacheRoot)
  grant
  deadline = do
    let authorizedWorkingDirectory =
          authorizedWriterCanonicalRoot cacheRoot
        authorizedDmgPath =
          authorizedWorkingDirectory
            </> Recipe.audiverisDmgFileName
              <> ".download"
    runProvisioningCommandInWriter
      cacheRoot
      []
      grant
      deadline
      (Internal.DownloadAudiverisDmg authorizedWorkingDirectory authorizedDmgPath)

mountAudiverisDmg ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  StagedAudiverisDmg w s q ->
  ProvisioningSession s ProvisioningOutcome
mountAudiverisDmg
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  staged = do
    let candidateRoot = stagedAudiverisCandidateRoot staged
        dmgPath =
          candidateRoot </> "tmp" </> Recipe.audiverisDmgFileName
        mountRoot =
          candidateRoot </> "tmp" </> "audiveris-dmg"
    exactDmg <-
      ProvisioningSession
        ( digestAuthorizedRegularFileExact
            engineRoot
            dmgPath
            Recipe.audiverisDmgSize
        )
    unless
      ( stableExecutableStatus
          (stagedAudiverisDmgStatus staged)
          (fst exactDmg)
          && snd exactDmg == stagedAudiverisDmgDigest staged
          && snd exactDmg == Recipe.audiverisDmgDigest
      )
      (failProvisioningSession "staged Audiveris DMG receipt changed before mount")
    ProvisioningSession
      ( ensureAuthorizedDirectoryTree
          "Audiveris private mount root"
          engineRoot
          mountRoot
      )
    workingDirectoryComponents <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Audiveris mount working directory"
            engineRoot
            candidateRoot
        )
    runProvisioningCommandInWriter
      engineRoot
      workingDirectoryComponents
      grant
      deadline
      ( Internal.MountAudiverisDmg
          authorizedWorkingDirectory
          dmgPath
          mountRoot
      )
    where
      authorizedWorkingDirectory =
        stagedAudiverisCandidateRoot staged

detachAudiverisDmg ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  FilePath ->
  ProvisioningSession s ProvisioningOutcome
detachAudiverisDmg
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  candidateRoot = do
    authorizedWorkingDirectory <-
      ProvisioningSession
        (authorizedWriterPath "Audiveris detach working directory" engineRoot candidateRoot)
    let authorizedMountRoot =
          authorizedWorkingDirectory </> "tmp" </> "audiveris-dmg"
    workingDirectoryComponents <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Audiveris detach working directory"
            engineRoot
            authorizedWorkingDirectory
        )
    runProvisioningCommandInWriter
      engineRoot
      workingDirectoryComponents
      grant
      deadline
      (Internal.DetachAudiverisDmg authorizedWorkingDirectory authorizedMountRoot)

queryPythonVersion ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  CandidatePythonTarget s ->
  ProvisioningSession s ProvisioningOutcome
queryPythonVersion
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  target = do
    let adapter = candidatePythonTargetInternalAdapter target
        artifactRoot = candidatePythonTargetRoot target
    identity <-
      requireCandidatePythonTarget adapter artifactRoot target
    authorizedArtifactRoot <-
      ProvisioningSession
        (authorizedWriterPath "Python version query root" engineRoot artifactRoot)
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Python version query root"
            engineRoot
            authorizedArtifactRoot
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.QueryPythonVersion adapter authorizedArtifactRoot)

queryPythonProvenance ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  CandidatePythonTarget s ->
  ProvisioningSession s ProvisioningOutcome
queryPythonProvenance
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  target = do
    let adapter = candidatePythonTargetInternalAdapter target
        artifactRoot = candidatePythonTargetRoot target
    identity <-
      requireCandidatePythonTarget adapter artifactRoot target
    authorizedArtifactRoot <-
      ProvisioningSession
        (authorizedWriterPath "Python provenance query root" engineRoot artifactRoot)
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Python provenance query root"
            engineRoot
            authorizedArtifactRoot
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      identity
      []
      []
      (Internal.QueryPythonProvenance adapter authorizedArtifactRoot)

pinnedPipRequirementSpec :: String
pinnedPipRequirementSpec =
  Internal.pinnedPipRequirement

pinnedPoetryBootstrapRequirementSpecs :: [String]
pinnedPoetryBootstrapRequirementSpecs =
  Internal.pinnedPoetryBootstrapRequirements

pinnedPythonRequirementSpecs :: ApplePythonAdapterId -> [String]
pinnedPythonRequirementSpecs (ApplePythonAdapterId adapter) =
  Internal.pinnedPythonRequirements adapter

audiverisPinnedVersion :: String
audiverisPinnedVersion =
  Internal.audiverisVersion

audiverisPinnedDmgFileName :: FilePath
audiverisPinnedDmgFileName =
  Internal.audiverisDmgFileName

audiverisPinnedDmgUrl :: String
audiverisPinnedDmgUrl =
  Internal.audiverisDmgUrl

runProvisioningCommandWithExecutable ::
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  [Internal.ProvisioningRuntimeLibraryIdentity] ->
  Internal.ProvisioningCommand ->
  ProvisioningSession s ProvisioningOutcome
runProvisioningCommandWithExecutable
  grant
  deadline
  identity
  packageClosures
  runtimeLibraries
  command = do
    validation <-
      ProvisioningSession (revalidateExecutableIdentity identity)
    case validation of
      Left failure ->
        pure
          ( ProvisioningRejected
              ( "resolved executable identity changed before bounded launch: "
                  <> failure
              )
          )
      Right () ->
        runProvisioningCommandWithIdentity
          grant
          deadline
          ( toKernelExecutableIdentity
              identity
              packageClosures
              runtimeLibraries
          )
          command

runProvisioningCommandWithExecutableInWriter ::
  AuthorizedWriterRoot ->
  [FilePath] ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  [Internal.ProvisioningRuntimeLibraryIdentity] ->
  Internal.ProvisioningCommand ->
  ProvisioningSession s ProvisioningOutcome
runProvisioningCommandWithExecutableInWriter
  authorizedRoot
  workingDirectoryComponents
  grant
  deadline
  identity
  packageClosures
  runtimeLibraries
  command = do
    validation <-
      ProvisioningSession (revalidateExecutableIdentity identity)
    case validation of
      Left failure ->
        pure
          ( ProvisioningRejected
              ( "resolved executable identity changed before bounded launch: "
                  <> failure
              )
          )
      Right () ->
        runProvisioningCommandWithIdentityInWriter
          authorizedRoot
          workingDirectoryComponents
          grant
          deadline
          ( toKernelExecutableIdentity
              identity
              packageClosures
              runtimeLibraries
          )
          command

toKernelExecutableIdentity ::
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  [Internal.ProvisioningRuntimeLibraryIdentity] ->
  Internal.ProvisioningExecutableIdentity
toKernelExecutableIdentity identity packageClosures runtimeLibraries =
  let status = resolvedExecutableCanonicalStatus identity
   in Internal.ProvisioningExecutableIdentity
        { Internal.provisioningExecutableConfiguredPath =
            resolvedExecutableConfiguredPath identity,
          Internal.provisioningExecutableCanonicalPath =
            resolvedExecutableCanonicalPath identity,
          Internal.provisioningExecutableDeviceId =
            fromIntegral (Posix.deviceID status),
          Internal.provisioningExecutableFileId =
            fromIntegral (Posix.fileID status),
          Internal.provisioningExecutableMode =
            fromIntegral (Posix.fileMode status),
          Internal.provisioningExecutableSize =
            fromIntegral (Posix.fileSize status),
          Internal.provisioningExecutableDigest =
            resolvedExecutableDigest identity,
          Internal.provisioningExecutablePackageClosures =
            packageClosures,
          Internal.provisioningExecutableRuntimeLibraries =
            runtimeLibraries
        }

runProvisioningCommandWithIdentity ::
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  Internal.ProvisioningExecutableIdentity ->
  Internal.ProvisioningCommand ->
  ProvisioningSession s ProvisioningOutcome
runProvisioningCommandWithIdentity
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  identity
  command =
    ProvisioningSession execution
    where
      execution =
        case Subprocess.compileProvisioningCommandWithExecutable
          command
          identity
          environment
          ( Subprocess.Timeout
              (Internal.positiveProvisioningTimeoutMicros timeout)
          ) of
          Left failure ->
            pure (ProvisioningRejected failure)
          Right boundedCommand ->
            toProvisioningOutcome deadline
              <$> Subprocess.runBoundedCommand boundedCommand

runProvisioningCommandWithIdentityInWriter ::
  AuthorizedWriterRoot ->
  [FilePath] ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  Internal.ProvisioningExecutableIdentity ->
  Internal.ProvisioningCommand ->
  ProvisioningSession s ProvisioningOutcome
runProvisioningCommandWithIdentityInWriter
  authorizedRoot
  workingDirectoryComponents
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  identity
  command =
    ProvisioningSession $ do
      validateWriterRootIdentity
        "bounded provisioning working directory"
        authorizedRoot
      case Subprocess.compileProvisioningCommandWithExecutableInMutationRoot
        command
        identity
        (authorizedWriterMutationRoot authorizedRoot)
        workingDirectoryComponents
        environment
        ( Subprocess.Timeout
            (Internal.positiveProvisioningTimeoutMicros timeout)
        ) of
        Left failure ->
          pure (ProvisioningRejected failure)
        Right boundedCommand -> do
          outcome <- Subprocess.runBoundedCommand boundedCommand
          validateWriterRootIdentity
            "bounded provisioning working directory"
            authorizedRoot
          pure (toProvisioningOutcome deadline outcome)

runProvisioningCommand ::
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  Internal.ProvisioningCommand ->
  ProvisioningSession s ProvisioningOutcome
runProvisioningCommand
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  command =
    ProvisioningSession execution
    where
      execution =
        case Subprocess.resolveProvisioningCommandExecutable
          command
          environment of
          Left failure ->
            pure (ProvisioningRejected failure)
          Right executablePath -> do
            identityResolution <-
              resolveExecutableIdentity executablePath
            case identityResolution of
              Left failure ->
                pure
                  ( ProvisioningRejected
                      ( "could not mint exact executable authority: "
                          <> failure
                      )
                  )
              Right identity ->
                case Subprocess.compileProvisioningCommandWithExecutable
                  command
                  (toKernelExecutableIdentity identity [] [])
                  environment
                  ( Subprocess.Timeout
                      (Internal.positiveProvisioningTimeoutMicros timeout)
                  ) of
                  Left failure ->
                    pure (ProvisioningRejected failure)
                  Right boundedCommand ->
                    toProvisioningOutcome deadline
                      <$> Subprocess.runBoundedCommand boundedCommand

runProvisioningCommandInWriter ::
  AuthorizedWriterRoot ->
  [FilePath] ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  Internal.ProvisioningCommand ->
  ProvisioningSession s ProvisioningOutcome
runProvisioningCommandInWriter
  authorizedRoot
  workingDirectoryComponents
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  command =
    ProvisioningSession $ do
      let executableResult =
            Subprocess.resolveProvisioningCommandExecutable
              command
              environment
      case executableResult of
        Left failure ->
          pure (ProvisioningRejected failure)
        Right executablePath -> do
          identityResolution <- resolveExecutableIdentity executablePath
          case identityResolution of
            Left failure ->
              pure
                ( ProvisioningRejected
                    ( "could not mint exact executable authority: "
                        <> failure
                    )
                )
            Right identity -> do
              validateWriterRootIdentity
                "bounded provisioning working directory"
                authorizedRoot
              case Subprocess.compileProvisioningCommandWithExecutableInMutationRoot
                command
                (toKernelExecutableIdentity identity [] [])
                (authorizedWriterMutationRoot authorizedRoot)
                workingDirectoryComponents
                environment
                ( Subprocess.Timeout
                    (Internal.positiveProvisioningTimeoutMicros timeout)
                ) of
                Left failure ->
                  pure (ProvisioningRejected failure)
                Right boundedCommand -> do
                  outcome <- Subprocess.runBoundedCommand boundedCommand
                  validateWriterRootIdentity
                    "bounded provisioning working directory"
                    authorizedRoot
                  pure (toProvisioningOutcome deadline outcome)

toProvisioningOutcome ::
  ProvisioningDeadline ->
  Subprocess.CommandOutcome ->
  ProvisioningOutcome
toProvisioningOutcome deadline outcome =
  case outcome of
    Subprocess.CommandSucceeded output ->
      ProvisioningSucceeded output
    Subprocess.CommandFailedFatal failure ->
      ProvisioningFailedFatal failure
    Subprocess.CommandFailedKernel failure ->
      ProvisioningFailedKernel failure
    Subprocess.CommandTimedOut _ ->
      ProvisioningTimedOut deadline
