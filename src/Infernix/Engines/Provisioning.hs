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
    InstalledPythonSourceIsolationReport (..),
    MachOFixturePlan (..),
    inspectMachOFixtureForTest,
    planMachOMetadataReadsForTest,
    machOInstallNameTargetForTest,
    pythonHomeClosureFileExcludedForTest,
    validRelativeClosureLinkForTest,
    shebangBindsHostInstallationForTest,
    supportedMachOMagicForTest,
    resolveMachOPathsFixtureForTest,
    resolveExactExecutableIdentityForTest,
    resolvedExecutableCanonicalIdentityMatchesForTest,
    resolvedExecutableIdentityMatchesForTest,
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
    executableMutationDuringHashRejectedForTest,
    relocationCandidateByteBoundForTest,
    validateRelocationCandidateByteSequenceForTest,
    darwinPoetryFrameworkHomeFromPyvenvForTest,
    resolveDarwinPoetryFrameworkHomeFromPyvenvForTest,
    ProvisioningClosureBound (..),
    provisioningClosureBoundForTest,
    MachOClosureDimensions (..),
    admitMachOClosureDimensionsForTest,
    admitPackageClosureFileForTest,
    admitPackageClosureTotalsForTest,
    completeAppleCandidate,
    completeApplePythonCandidateWithSourceIsolation,
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
    provisioningProjectExecutableReady,
    provisioningProjectReadFile,
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
    provisioningWriteBytesWithParentSwapPauseForTest,
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
    provisioningInterpretArtifactRootMutationForTest,
    provisioningReconcileArtifactRoot,
    installPoetryProject,
    installPoetryProjectWithGroups,
    createPoetryProjectVenv,
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
    extractAudiverisJavaCppNatives,
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
import Control.Monad (foldM, unless, void, when, zipWithM)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson qualified as Aeson
import Data.Aeson.Key qualified as AesonKey
import Data.Aeson.KeyMap qualified as AesonKeyMap
import Data.Aeson.Types qualified as AesonTypes
import Data.Bits (shiftL, (.&.), (.|.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.Char (isAscii, isAsciiLower, isAsciiUpper, isDigit)
import Data.List qualified as List
import Data.Maybe (catMaybes, isJust, mapMaybe)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Data.Word (Word32, Word64, Word8)
import Infernix.Cluster.Subprocess qualified as Subprocess
import Infernix.Config (Paths (..))
import Infernix.Engines.Artifact qualified as Artifact
import Infernix.Engines.Artifact.Activation qualified as ArtifactActivation
import Infernix.Engines.Artifact.Identity qualified as ArtifactIdentity
import Infernix.Engines.Artifact.Internal qualified as ArtifactInternal
import Infernix.Engines.Artifact.Loader qualified as ArtifactLoader
import Infernix.Engines.Artifact.Recipe qualified as Recipe
import Infernix.Engines.Artifact.Target
  ( NativeArtifactLoaderEvidence (..),
    NativeArtifactLoaderObjectEvidence (..),
    NativeArtifactTarget,
    NativeArtifactTargetEvidence,
    nativeArtifactTarget,
    nativeArtifactTargetArchitecture,
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
    OpenFileFlags (cloexec, creat, directory, exclusive, nofollow, nonBlock, trunc),
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
import System.Posix.Types
  ( ByteCount,
    DeviceID,
    Fd,
    FileID,
    FileMode,
    FileOffset,
  )
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

data InstalledPythonSourceIsolationReport
  = InstalledPythonSourceIsolationReport
  { installedPythonSourceIsolationReportAdapter :: !ApplePythonAdapterId,
    installedPythonSourceIsolationReportInstallRoot :: !FilePath,
    installedPythonSourceIsolationReportArtifactDigest :: !Text,
    installedPythonSourceIsolationReportReceiptDigest :: !Text,
    installedPythonSourceIsolationReportDirectoryCount :: !Int,
    installedPythonSourceIsolationReportFileCount :: !Int
  }
  deriving (Eq, Show)

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
            totalClosureBytes =
              sum
                (map Internal.provisioningPackageClosureBytes closures)
            totalClosureFiles =
              sum
                (map Internal.provisioningPackageClosureFiles closures)
        unless
          ( totalClosureBytes <= maximumPoetryClosureBytes
              && totalClosureFiles <= maximumPoetryClosureFiles
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
    pure (displayCaughtProvisioningFailure validation)

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
    _candidatePythonTargetIdentity <-
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
      -- The Python home is scanned as well as the candidate venv. Its
      -- `lib-dynload` extension modules (`_lzma`, `_ssl`, `_decimal`, …) are
      -- dlopened rather than linked by the interpreter, so nothing reaches them
      -- through a dependency edge from the interpreter alone. Scanning only the
      -- venv left their Homebrew dependencies undiscovered and unvendored, and
      -- the sealed runner then loaded `liblzma`, `libcrypto`, and `libmpdec`
      -- from the /host/ -- exactly the escape the installed smoke's
      -- unsealed-library check exists to catch.
      resolveExactMachORuntimeLibraries
        pythonIdentity
        [candidateVenvIdentity, sourceHomeIdentity]
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
        Internal.LlamaCppCliAdapter -> pure "llama-completion"
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
      javaCppCacheRoot = ownedCandidate </> "javacpp-cache"
      launcher =
        appRoot
          </> "Contents"
          </> "MacOS"
          </> "Audiveris"
  authorizedApp <-
    authorizeEnginePath "Audiveris fixed application root" writer appRoot
  authorizedJavaCppCache <-
    authorizeEnginePath "Audiveris fixed JavaCPP cache root" writer javaCppCacheRoot
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
  javaCppCacheIdentity <-
    ProvisioningSession
      ( resolvePackageClosureIdentity
          Internal.ProvisioningArtifactRootClosure
          authorizedJavaCppCache
      )
  javaCppCacheImages <-
    ProvisioningSession (scanPackageClosureMachOFiles javaCppCacheIdentity)
  when
    (null javaCppCacheImages)
    (failProvisioningSession "Audiveris JavaCPP cache contains no Mach-O runtime image")
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
        },
      InstalledRuntimeSource
        { installedRuntimeSourcePath = authorizedJavaCppCache,
          installedRuntimeOwnedPath = authorizedJavaCppCache,
          installedRuntimeSourceDigest =
            Internal.provisioningPackageClosureDigest javaCppCacheIdentity,
          installedRuntimeSourceFiles =
            Internal.provisioningPackageClosureFiles javaCppCacheIdentity,
          installedRuntimeSourceBytes =
            Internal.provisioningPackageClosureBytes javaCppCacheIdentity
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
      (resolvedExecutableCanonicalIdentityMatches identity observed)
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
          (resolvedExecutableCanonicalIdentityMatches identity finalObserved)
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

-- | Compare an identity against a re-resolution performed from its own
-- canonical path.
--
-- The re-resolution's /configured/ path is that canonical path by
-- construction, so it must not be compared against the original's configured
-- path: those differ whenever the tool was reached through a symlink, which is
-- the normal case for a Homebrew-managed interpreter such as
-- @\/opt\/homebrew\/bin\/python3.12@. Exactness is preserved by requiring the
-- canonical path, canonical status (device, inode, mode, size, mtime, ctime),
-- and content digest to agree, and by requiring the observed resolution to be
-- genuinely canonical -- its configured and canonical sides must name the same
-- object -- so a symlink swapped in at the canonical path is still rejected.
resolvedExecutableCanonicalIdentityMatches ::
  ResolvedExecutableIdentity ->
  ResolvedExecutableIdentity ->
  Bool
resolvedExecutableCanonicalIdentityMatches expected observed =
  normalise (resolvedExecutableCanonicalPath expected)
    == normalise (resolvedExecutableCanonicalPath observed)
    && normalise (resolvedExecutableConfiguredPath observed)
      == normalise (resolvedExecutableCanonicalPath observed)
    && stableExecutableStatus
      (resolvedExecutableCanonicalStatus expected)
      (resolvedExecutableCanonicalStatus observed)
    && stableExecutableStatus
      (resolvedExecutableConfiguredStatus observed)
      (resolvedExecutableCanonicalStatus observed)
    && resolvedExecutableDigest expected
      == resolvedExecutableDigest observed

executableIdentityHasExecuteBit :: ResolvedExecutableIdentity -> Bool
executableIdentityHasExecuteBit identity =
  executableFileMode (resolvedExecutableCanonicalStatus identity)

-- | Whether an observed status carries an execute bit for anyone.
executableFileMode :: Posix.FileStatus -> Bool
executableFileMode status =
  Posix.fileMode status
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
  pure (displayCaughtProvisioningFailure result)

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
          contents <- readProvisioningDescriptorChunk descriptor maximumBytes
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
      pythonHomeRoot <- resolvePoetryPythonHome interpreterPath
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

resolvePoetryPythonHome :: FilePath -> IO FilePath
resolvePoetryPythonHome interpreterPath
  | SystemInfo.os /= "darwin" =
      takeDirectory . takeDirectory
        <$> Directory.canonicalizePath interpreterPath
  | otherwise =
      mask $ \restore -> do
        let venvRoot = takeDirectory (takeDirectory interpreterPath)
        listedStatus <- Posix.getSymbolicLinkStatus venvRoot
        descriptor <-
          openFd
            venvRoot
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
                ( Posix.isDirectory openedStatus
                    && stableExecutableStatus listedStatus openedStatus
                )
                (ioError (userError "Poetry venv changed before Python-home resolution"))
              configDescriptor <-
                openFdAt
                  (Just descriptor)
                  "pyvenv.cfg"
                  ReadOnly
                  defaultFileFlags
                    { nofollow = True,
                      nonBlock = True,
                      cloexec = True
                    }
              frameworkHome <-
                finallyPreservingPrimary
                  ( do
                      configStatus <- Posix.getFdStatus configDescriptor
                      unless
                        ( Posix.isRegularFile configStatus
                            && fromIntegral (Posix.fileSize configStatus)
                              <= maximumRelocationConfigBytes
                        )
                        (ioError (userError "Poetry pyvenv.cfg is not a bounded regular file"))
                      contents <-
                        readExactProvisioningDescriptorBytes
                          configDescriptor
                          (fromIntegral (Posix.fileSize configStatus))
                      text <-
                        either
                          (ioError . userError . ("Poetry pyvenv.cfg is not UTF-8: " <>) . show)
                          pure
                          (TextEncoding.decodeUtf8' contents)
                      homeResult <-
                        resolveDarwinPoetryFrameworkHomeFromPyvenv text
                      home <- either (ioError . userError) pure homeResult
                      finalConfigStatus <- Posix.getFdStatus configDescriptor
                      reopenedConfigStatus <- reopenFileEntryStatus descriptor "pyvenv.cfg"
                      unless
                        ( stableExecutableStatus configStatus finalConfigStatus
                            && stableExecutableStatus finalConfigStatus reopenedConfigStatus
                        )
                        (ioError (userError "Poetry pyvenv.cfg changed during Python-home resolution"))
                      pure home
                  )
                  (closeFd configDescriptor)
              canonicalHome <- Directory.canonicalizePath frameworkHome
              homeStatus <- Posix.getSymbolicLinkStatus canonicalHome
              finalStatus <- Posix.getFdStatus descriptor
              finalPathStatus <- Posix.getSymbolicLinkStatus venvRoot
              unless
                ( normalise canonicalHome == normalise frameworkHome
                    && Posix.isDirectory homeStatus
                    && stableExecutableStatus openedStatus finalStatus
                    && stableExecutableStatus finalStatus finalPathStatus
                )
                (ioError (userError "Poetry Python framework home is not a stable real directory"))
              pure canonicalHome
          )
          (closeFd descriptor)

darwinPoetryFrameworkHomeFromPyvenvForTest ::
  Text ->
  Either String FilePath
darwinPoetryFrameworkHomeFromPyvenvForTest contents = do
  sourceHome <- darwinPoetryHomeFromPyvenv contents
  let frameworkHome = takeDirectory sourceHome
  unlessEither
    ( normalise sourceHome
        == normalise (frameworkHome </> "bin")
        && validDarwinPythonFrameworkHome frameworkHome
    )
    "Poetry pyvenv.cfg does not name a fixed Darwin Python.framework version"
  pure frameworkHome

darwinPoetryHomeFromPyvenv ::
  Text ->
  Either String FilePath
darwinPoetryHomeFromPyvenv contents = do
  let homeValues =
        [ Text.unpack value
        | line <- Text.lines contents,
          Just value <- [Text.stripPrefix "home = " line]
        ]
      executableValues =
        [ Text.unpack value
        | line <- Text.lines contents,
          Just value <- [Text.stripPrefix "executable = " line]
        ]
  sourceHome <- requireSinglePyvenvValue "home" homeValues
  unlessEither
    ( validNormalizedAbsolutePath sourceHome
        && length executableValues <= 1
    )
    "Poetry pyvenv.cfg does not name one normalized absolute Python home"
  pure sourceHome

resolveDarwinPoetryFrameworkHomeFromPyvenv ::
  Text ->
  IO (Either String FilePath)
resolveDarwinPoetryFrameworkHomeFromPyvenv contents =
  case darwinPoetryHomeFromPyvenv contents of
    Left failure -> pure (Left failure)
    Right sourceHome -> do
      result <-
        try @IOException $ do
          canonicalBin <- Directory.canonicalizePath sourceHome
          let frameworkHome = takeDirectory canonicalBin
          unless
            ( normalise canonicalBin
                == normalise (frameworkHome </> "bin")
                && validDarwinPythonFrameworkHome frameworkHome
            )
            ( ioError
                ( userError
                    "Poetry pyvenv.cfg home does not resolve inside a fixed Darwin Python.framework version"
                )
            )
          finalCanonicalBin <- Directory.canonicalizePath sourceHome
          unless
            (normalise finalCanonicalBin == normalise canonicalBin)
            (ioError (userError "Poetry pyvenv.cfg home changed during resolution"))
          pure frameworkHome
      pure (displayCaughtProvisioningFailure result)

resolveDarwinPoetryFrameworkHomeFromPyvenvForTest ::
  Text ->
  IO (Either String FilePath)
resolveDarwinPoetryFrameworkHomeFromPyvenvForTest =
  resolveDarwinPoetryFrameworkHomeFromPyvenv

validDarwinPythonFrameworkHome :: FilePath -> Bool
validDarwinPythonFrameworkHome frameworkHome =
  case reverse (splitDirectories (normalise frameworkHome)) of
    version : "Versions" : "Python.framework" : _ ->
      validFixedPathComponent version
    _ -> False

data MachOInspection = MachOInspection
  { machODependencies :: ![FilePath],
    -- | The subset of 'machODependencies' declared through a weak or lazy load
    -- command. @dyld@ permits these to be absent at run time, so one that no
    -- inherited @LC_RPATH@ resolves is skipped rather than failing the closure.
    -- A required dependency that does not resolve is still fatal.
    machOOptionalDependencies :: ![FilePath],
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
maximumMachOImages = 8192

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
maximumMachORuntimeBytes = 4 * 1024 * 1024 * 1024

maximumMachOInspectionBytes :: Integer
maximumMachOInspectionBytes = 4 * 1024 * 1024 * 1024

maximumMachOMetadataBytes :: Integer
maximumMachOMetadataBytes = 4 * 1024 * 1024

maximumMachOLoadCommands :: Word32
maximumMachOLoadCommands = 4096

maximumMachOLoadCommandBytes :: Word32
maximumMachOLoadCommandBytes = 4 * 1024 * 1024

maximumExactRuntimeFileBytes :: Integer
maximumExactRuntimeFileBytes = 2 * 1024 * 1024 * 1024

resolvePoetryRuntimeLibraries ::
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  IO (Either String [Internal.ProvisioningRuntimeLibraryIdentity])
resolvePoetryRuntimeLibraries interpreterIdentity packageClosures =
  case SystemInfo.os of
    "darwin" ->
      resolvePoetryMachORuntimeLibraries interpreterIdentity packageClosures
    "linux" ->
      resolvePoetryElfRuntimeLibraries interpreterIdentity packageClosures
    unsupported ->
      pure (Left ("unsupported Poetry runtime platform: " <> unsupported))

resolvePoetryElfRuntimeLibraries ::
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  IO (Either String [Internal.ProvisioningRuntimeLibraryIdentity])
resolvePoetryElfRuntimeLibraries interpreterIdentity packageClosures = do
  result <-
    try @IOException $ do
      evidence <-
        ArtifactLoader.observeNativeArtifactLoaderEvidence
          (resolvedExecutableCanonicalPath interpreterIdentity)
          (map Internal.provisioningPackageClosureRoot packageClosures)
      pure
        [ Internal.ProvisioningRuntimeLibraryIdentity
            { Internal.provisioningRuntimeLibraryLeafName =
                takeFileName (loaderObjectConfiguredPath object),
              Internal.provisioningRuntimeLibraryConfiguredPath =
                loaderObjectConfiguredPath object,
              Internal.provisioningRuntimeLibraryCanonicalPath =
                loaderObjectCanonicalPath object,
              Internal.provisioningRuntimeLibraryDeviceId =
                loaderObjectCanonicalDeviceId object,
              Internal.provisioningRuntimeLibraryFileId =
                loaderObjectCanonicalFileId object,
              Internal.provisioningRuntimeLibraryMode =
                loaderObjectCanonicalMode object,
              Internal.provisioningRuntimeLibrarySize =
                loaderObjectCanonicalSize object,
              Internal.provisioningRuntimeLibraryDigest =
                loaderObjectDigest object
            }
        | object <- loaderEvidenceObjects evidence,
          loaderObjectCanonicalPath object
            /= resolvedExecutableCanonicalPath interpreterIdentity
        ]
  pure (either (Left . displayException) Right result)

resolvePoetryMachORuntimeLibraries ::
  ResolvedExecutableIdentity ->
  [Internal.ProvisioningPackageClosureIdentity] ->
  IO (Either String [Internal.ProvisioningRuntimeLibraryIdentity])
resolvePoetryMachORuntimeLibraries interpreterIdentity packageClosures = do
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
      let closureRoots =
            map Internal.provisioningPackageClosureRoot packageClosures
      initialDependencies <-
        resolveMachODependencies
          closureRoots
          (resolvedExecutableCanonicalPath interpreterIdentity)
          executableDirectory
          executableRpaths
          (machOOptionalDependencies interpreterInspection)
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
      -- dyld resolves an @rpath dependency against the stack accumulated down
      -- the whole load chain, never against the dependent image alone. A
      -- library discovered by scanning the package closure is not a load root:
      -- it is reached through some loader in that same closure, and that
      -- loader supplies the stack. MLX is the concrete case -- its
      -- `core.<abi>.so` declares `LC_RPATH @loader_path/lib` and loads
      -- `@rpath/libmlx.dylib`, while `libmlx.dylib` declares no rpath of its
      -- own and loads `@rpath/libjaccl.dylib` from that same directory. Walked
      -- in isolation, `libmlx.dylib` has an empty stack and cannot resolve it.
      -- Scanned roots therefore inherit every rpath this closure declares:
      -- each is one a real loader here supplies, which is exactly the set dyld
      -- could use.
      (closureDeclaredRpaths, seededState) <-
        foldM
          (accumulateClosureRpaths executableDirectory)
          ([], initialState)
          closureMachOIdentities
      let scannedRootRpaths =
            List.nub (executableRpaths <> closureDeclaredRpaths)
      unless
        (length scannedRootRpaths <= maximumMachORpathStack)
        (ioError (userError "Poetry Mach-O closure rpath stack exceeds its fixed bound"))
      let initialQueue =
            List.sortOn
              machOQueuePath
              ( [ MachOQueueEntry
                    (Internal.provisioningRuntimeLibraryConfiguredPath library)
                    scannedRootRpaths
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
          closureRoots
          executableDirectory
          seededState
          initialQueue
      validateMachOClosureState finalState
      pure
        ( List.sortOn
            Internal.provisioningRuntimeLibraryLeafName
            (machORuntimeLibraries finalState)
        )
  pure (either (Left . displayException) Right result)

-- | Fold one scanned closure image's declared @LC_RPATH@ entries, expanded
-- relative to that image, into the closure's rpath set.
--
-- The inspection goes through 'cachedMachOInspection' so the image, byte, and
-- metadata bounds account for it exactly once, whether it is reached here or
-- later through a dependency edge.
accumulateClosureRpaths ::
  FilePath ->
  ([FilePath], MachOClosureState) ->
  Internal.ProvisioningRuntimeLibraryIdentity ->
  IO ([FilePath], MachOClosureState)
accumulateClosureRpaths
  executableDirectory
  (rpathsSoFar, state)
  library = do
    let libraryPath =
          Internal.provisioningRuntimeLibraryCanonicalPath library
    identity <- resolveExactExecutableIdentity libraryPath
    unless
      (resolvedIdentityMatchesRuntimeIdentity identity library)
      (ioError (userError ("Mach-O closure image changed before rpath seeding: " <> libraryPath)))
    (inspection, nextState) <- cachedMachOInspection state identity
    expanded <-
      requireMachOResolution
        ( expandMachORpathStack
            libraryPath
            executableDirectory
            []
            (machORpaths inspection)
        )
    pure (List.nub (rpathsSoFar <> expanded), nextState)

walkMachOClosure ::
  [FilePath] ->
  FilePath ->
  MachOClosureState ->
  [MachOQueueEntry] ->
  IO MachOClosureState
walkMachOClosure closureRoots executableDirectory state queue =
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
        then walkMachOClosure closureRoots executableDirectory state remaining
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
              closureRoots
              canonicalPath
              executableDirectory
              currentRpaths
              (machOOptionalDependencies inspection)
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
            closureRoots
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
      -- Name the bound that was exceeded and by how much: a single combined
      -- message cannot be acted on without re-running the whole materialization.
      unless (length nextInspections <= maximumMachOImages) $
        ioError
          ( userError
              ( "Poetry Mach-O inspection exceeds its image bound: "
                  <> show (length nextInspections)
                  <> " > "
                  <> show maximumMachOImages
              )
          )
      unless (nextBytes <= maximumMachOInspectionBytes) $
        ioError
          ( userError
              ( "Poetry Mach-O inspection exceeds its byte bound: "
                  <> show nextBytes
                  <> " > "
                  <> show maximumMachOInspectionBytes
              )
          )
      unless (nextMetadata <= maximumMachOMetadataBytes) $
        ioError
          ( userError
              ( "Poetry Mach-O inspection exceeds its metadata bound: "
                  <> show nextMetadata
                  <> " > "
                  <> show maximumMachOMetadataBytes
              )
          )
      pure
        ( inspection,
          state
            { machOInspections = nextInspections,
              machOBytesInspected = nextBytes,
              machOMetadataObserved = nextMetadata
            }
        )

validateMachOClosureState :: MachOClosureState -> IO ()
validateMachOClosureState state =
  either
    (ioError . userError)
    pure
    (admitMachOClosureDimensions (machOClosureDimensions state))

machOClosureDimensions :: MachOClosureState -> MachOClosureDimensions
machOClosureDimensions state =
  MachOClosureDimensions
    { machOClosureLibraryCount = fromIntegral (length libraries),
      machOClosureRuntimeBytes =
        sum (map Internal.provisioningRuntimeLibrarySize libraries),
      machOClosureEdges = machOEdgesObserved state,
      machOClosureInspectionBytes = machOBytesInspected state,
      machOClosureMetadataBytes = machOMetadataObserved state
    }
  where
    libraries = machORuntimeLibraries state

-- | The five whole-closure dimensions the Mach-O walk is bounded on.
--
-- Measured against the seven Apple artifacts: @coreml-native@ is the largest at
-- 811.9 MiB of Mach-O images, of which 322.3 MiB is a single
-- @torch\/lib\/libtorch_cpu.dylib@, so both the inspection total and the
-- vendored runtime total sit under a 4 GiB bound with roughly fivefold
-- headroom. The inspection total legitimately exceeds the vendored total,
-- because every scanned closure image is inspected while only the images a
-- loader actually reaches are vendored.
data MachOClosureDimensions = MachOClosureDimensions
  { machOClosureLibraryCount :: !Integer,
    machOClosureRuntimeBytes :: !Integer,
    machOClosureEdges :: !Integer,
    machOClosureInspectionBytes :: !Integer,
    machOClosureMetadataBytes :: !Integer
  }
  deriving (Eq, Show)

-- | Name the dimension that was exceeded and by how much. A single combined
-- message cannot be acted on without re-running the whole materialization,
-- which costs tens of minutes each time.
admitMachOClosureDimensions ::
  MachOClosureDimensions ->
  Either String ()
admitMachOClosureDimensions dimensions =
  case mapMaybe exceeded boundedDimensions of
    [] -> Right ()
    failure : _ -> Left failure
  where
    boundedDimensions =
      [ ( "runtime library count",
          machOClosureLibraryCount dimensions,
          fromIntegral maximumMachORuntimeLibraries
        ),
        ( "runtime byte",
          machOClosureRuntimeBytes dimensions,
          maximumMachORuntimeBytes
        ),
        ("edge", machOClosureEdges dimensions, maximumMachOEdges),
        ( "inspection byte",
          machOClosureInspectionBytes dimensions,
          maximumMachOInspectionBytes
        ),
        ( "metadata byte",
          machOClosureMetadataBytes dimensions,
          maximumMachOMetadataBytes
        )
      ]
    exceeded (label, observed, limit)
      | observed <= limit = Nothing
      | otherwise =
          Just
            ( "Poetry Mach-O closure exceeds its "
                <> label
                <> " bound: "
                <> show observed
                <> " > "
                <> show limit
            )

admitMachOClosureDimensionsForTest ::
  MachOClosureDimensions ->
  Either String ()
admitMachOClosureDimensionsForTest = admitMachOClosureDimensions

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

-- | Resolve one executable identity for a fixture.
--
-- The identity carries live @stat@ results, so the comparison it feeds cannot
-- be exercised from synthesized values; a fixture has to resolve real paths.
-- This is the surface the pure regression block cannot reach.
resolveExactExecutableIdentityForTest ::
  FilePath ->
  IO ResolvedExecutableIdentity
resolveExactExecutableIdentityForTest = resolveExactExecutableIdentity

-- | The canonical-versus-configured comparison, for a fixture.
resolvedExecutableCanonicalIdentityMatchesForTest ::
  ResolvedExecutableIdentity ->
  ResolvedExecutableIdentity ->
  Bool
resolvedExecutableCanonicalIdentityMatchesForTest =
  resolvedExecutableCanonicalIdentityMatches

-- | The strict configured-path comparison, for a fixture. Exported beside the
-- canonical form because the distinction between them is the property under
-- test: the strict form rejects the ordinary symlinked-interpreter case that
-- the canonical form must accept.
resolvedExecutableIdentityMatchesForTest ::
  ResolvedExecutableIdentity ->
  ResolvedExecutableIdentity ->
  Bool
resolvedExecutableIdentityMatchesForTest = resolvedExecutableIdentityMatches

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
                  ( ioError
                      ( userError
                          ( "Poetry package closure has too many Mach-O images: "
                              <> show (length identities)
                              <> " > "
                              <> show maximumMachOImages
                          )
                      )
                  )
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
    leadingHeader <- readProvisioningDescriptorChunk descriptor 12
    maybeIdentity <-
      if supportedMachOMagic leadingHeader
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

-- | Whether a file's leading bytes identify it as a Mach-O image.
--
-- The universal (fat) magic @0xCAFEBABE@ is byte-identical to the Java class
-- file magic, so the four-byte magic alone cannot tell them apart. That matters
-- here because the Audiveris artifact is a JVM application whose bundle is full
-- of @.class@ files: classifying one as a Mach-O admits it as a closure
-- candidate, and it then fails the full parse and takes the whole
-- materialization with it.
--
-- A fat header is therefore required to be structurally credible: its
-- architecture count must be within the same bound the parser enforces, and its
-- first architecture must name a CPU type Mach-O actually defines. In a Java
-- class file those same bytes are the minor and major class-format versions,
-- which land far outside a plausible architecture count.
supportedMachOMagic :: ByteString.ByteString -> Bool
supportedMachOMagic leading
  | ByteString.take 4 leading == ByteString.pack [0xcf, 0xfa, 0xed, 0xfe] = True
  | ByteString.take 4 leading
      `elem` [ ByteString.pack [0xca, 0xfe, 0xba, 0xbe],
               ByteString.pack [0xca, 0xfe, 0xba, 0xbf]
             ] =
      case (readWord32BE leading 4, readWord32BE leading 8) of
        (Right architectureCount, Right firstCpuType) ->
          architectureCount > 0
            && architectureCount <= maximumFatArchitectures
            && firstCpuType `elem` machOCpuTypes
        _ -> False
  | otherwise = False

-- | The architecture-count bound the fat Mach-O parser enforces.
maximumFatArchitectures :: Word32
maximumFatArchitectures = 32

-- | CPU types Mach-O defines, used to tell a fat header from a class file.
machOCpuTypes :: [Word32]
machOCpuTypes =
  [ 7, -- x86
    0x01000007, -- x86_64
    12, -- arm
    0x0100000c, -- arm64
    0x0200000c, -- arm64_32
    18, -- powerpc
    0x01000012 -- powerpc64
  ]

inspectExactMachOImage ::
  ResolvedExecutableIdentity ->
  IO MachOInspection
inspectExactMachOImage identity =
  mask $ \restore -> do
    let path = resolvedExecutableCanonicalPath identity
        expectedStatus =
          resolvedExecutableCanonicalStatus identity
        expectedSize :: Integer
        expectedSize = fromIntegral (Posix.fileSize expectedStatus)
    unless
      ( expectedSize >= 0
          && expectedSize <= maximumExactRuntimeFileBytes
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
            (ioError (userError "Mach-O image changed before metadata read"))
          inspection <-
            inspectMachOMetadataDescriptor descriptor expectedSize
          finalStatus <- Posix.getFdStatus descriptor
          finalPathStatus <- Posix.getSymbolicLinkStatus path
          unless
            ( stableExecutableStatus openedStatus finalStatus
                && stableExecutableStatus finalStatus finalPathStatus
            )
            (ioError (userError "Mach-O image changed during metadata read"))
          pure inspection
      )
      (closeFd descriptor)

-- | Inspect only the bounded metadata dyld consumes from a Mach-O image.
--
-- The exact identity has already streamed and hashed the complete payload.
-- Retaining that payload again merely to parse its header allocated one
-- file-sized pinned buffer for large libraries such as @libtorch_cpu.dylib@;
-- a short multi-read can also require a concatenation copy. A thin image needs
-- its 32-byte header plus at most 4 MiB of load commands. A fat image
-- additionally needs its bounded architecture table before the selected arm64
-- slice can be addressed. Every read remains on the retained no-follow
-- descriptor, and the caller rechecks both that descriptor and the path after
-- this inspection completes.
inspectMachOMetadataDescriptor ::
  Fd ->
  Integer ->
  IO MachOInspection
inspectMachOMetadataDescriptor descriptor imageBytes = do
  leading <- readProvisioningDescriptorRange descriptor 0 8
  if
    | ByteString.take 4 leading == thinMachOMagic -> do
        header <- readProvisioningDescriptorRange descriptor 0 32
        metadataBytes <-
          requireMachOResolution
            (thinMachOMetadataReadBytes imageBytes header)
        contents <-
          readProvisioningDescriptorRange descriptor 0 metadataBytes
        requireMachOResolution (parseThinMachO contents)
    | ByteString.take 4 leading == fat32MachOMagic ->
        inspectFatMachOMetadataDescriptor descriptor imageBytes False leading
    | ByteString.take 4 leading == fat64MachOMagic ->
        inspectFatMachOMetadataDescriptor descriptor imageBytes True leading
    | otherwise ->
        ioError (userError "unsupported or non-arm64 Mach-O magic")

inspectFatMachOMetadataDescriptor ::
  Fd ->
  Integer ->
  Bool ->
  ByteString.ByteString ->
  IO MachOInspection
inspectFatMachOMetadataDescriptor descriptor imageBytes is64 leading = do
  tableBytes <-
    requireMachOResolution
      (fatMachOArchitectureTableBytes imageBytes is64 leading)
  architectureTable <-
    readProvisioningDescriptorRange descriptor 0 tableBytes
  (sliceOffset, sliceBytes) <-
    requireMachOResolution
      (selectFatMachOArm64Range is64 architectureTable)
  requireMachOResolution
    (validateFatMachOSliceRange imageBytes sliceOffset sliceBytes)
  sliceHeader <-
    readProvisioningDescriptorRange
      descriptor
      (fromIntegral sliceOffset)
      32
  metadataBytes <-
    requireMachOResolution
      (thinMachOMetadataReadBytes (fromIntegral sliceBytes) sliceHeader)
  contents <-
    readProvisioningDescriptorRange
      descriptor
      (fromIntegral sliceOffset)
      metadataBytes
  requireMachOResolution (parseThinMachO contents)

thinMachOMagic :: ByteString.ByteString
thinMachOMagic = ByteString.pack [0xcf, 0xfa, 0xed, 0xfe]

fat32MachOMagic :: ByteString.ByteString
fat32MachOMagic = ByteString.pack [0xca, 0xfe, 0xba, 0xbe]

fat64MachOMagic :: ByteString.ByteString
fat64MachOMagic = ByteString.pack [0xca, 0xfe, 0xba, 0xbf]

thinMachOMetadataReadBytes ::
  Integer ->
  ByteString.ByteString ->
  Either String Integer
thinMachOMetadataReadBytes imageBytes header = do
  unlessEither
    (imageBytes >= 32 && ByteString.take 4 header == thinMachOMagic)
    "Mach-O slice is not little-endian 64-bit"
  cpuType <- readWord32LE header 4
  unlessEither
    (cpuType == 0x0100000c)
    "Mach-O slice is not arm64"
  commandCount <- readWord32LE header 16
  commandBytes <- readWord32LE header 20
  let metadataBytes = 32 + fromIntegral commandBytes
  unlessEither
    ( commandCount <= maximumMachOLoadCommands
        && commandBytes <= maximumMachOLoadCommandBytes
        && metadataBytes <= imageBytes
    )
    "Mach-O load-command table exceeds its fixed bound"
  pure metadataBytes

fatMachOArchitectureTableBytes ::
  Integer ->
  Bool ->
  ByteString.ByteString ->
  Either String Integer
fatMachOArchitectureTableBytes imageBytes is64 leading = do
  architectureCount <- readWord32BE leading 4
  unlessEither
    (architectureCount > 0 && architectureCount <= maximumFatArchitectures)
    "fat Mach-O architecture count is invalid"
  let recordBytes :: Integer
      recordBytes = if is64 then 32 else 20
      tableBytes = 8 + fromIntegral architectureCount * recordBytes
  unlessEither
    (tableBytes <= imageBytes)
    "fat Mach-O architecture table is out of bounds"
  pure tableBytes

validateFatMachOSliceRange ::
  Integer ->
  Word64 ->
  Word64 ->
  Either String ()
validateFatMachOSliceRange imageBytes sliceOffset sliceBytes = do
  let offset = fromIntegral sliceOffset
      bytes = fromIntegral sliceBytes
  unlessEither
    ( bytes >= 32
        && offset <= imageBytes
        && bytes <= imageBytes - offset
    )
    "fat Mach-O slice is out of bounds"

-- | Pure regression surface for the exact read ranges production derives.
-- The first bytes must contain a complete thin header or fat architecture
-- table; a fat image additionally supplies the selected arm64 slice header.
planMachOMetadataReadsForTest ::
  Integer ->
  ByteString.ByteString ->
  Maybe ByteString.ByteString ->
  Either String [(Integer, Integer)]
planMachOMetadataReadsForTest imageBytes outerMetadata maybeSliceHeader
  | ByteString.take 4 outerMetadata == thinMachOMagic = do
      metadataBytes <-
        thinMachOMetadataReadBytes imageBytes outerMetadata
      pure [(0, metadataBytes)]
  | ByteString.take 4 outerMetadata == fat32MachOMagic =
      planFatMachOMetadataReadsForTest imageBytes False outerMetadata maybeSliceHeader
  | ByteString.take 4 outerMetadata == fat64MachOMagic =
      planFatMachOMetadataReadsForTest imageBytes True outerMetadata maybeSliceHeader
  | otherwise = Left "unsupported or non-arm64 Mach-O magic"

planFatMachOMetadataReadsForTest ::
  Integer ->
  Bool ->
  ByteString.ByteString ->
  Maybe ByteString.ByteString ->
  Either String [(Integer, Integer)]
planFatMachOMetadataReadsForTest imageBytes is64 architectureTable maybeSliceHeader = do
  tableBytes <-
    fatMachOArchitectureTableBytes imageBytes is64 architectureTable
  unlessEither
    (fromIntegral (ByteString.length architectureTable) >= tableBytes)
    "fat Mach-O architecture table is truncated"
  (sliceOffset, sliceBytes) <-
    selectFatMachOArm64Range is64 architectureTable
  validateFatMachOSliceRange imageBytes sliceOffset sliceBytes
  sliceHeader <-
    maybe
      (Left "fat Mach-O arm64 slice header is missing")
      Right
      maybeSliceHeader
  metadataBytes <-
    thinMachOMetadataReadBytes (fromIntegral sliceBytes) sliceHeader
  pure
    [ (0, tableBytes),
      (fromIntegral sliceOffset, metadataBytes)
    ]

-- | Read exactly one small, positioned Mach-O metadata range. The fixed cap is
-- deliberately the thin header plus the closed load-command bound; this helper
-- cannot regress into another whole-image allocation without first widening a
-- named invariant.
readProvisioningDescriptorRange ::
  Fd ->
  Integer ->
  Integer ->
  IO ByteString.ByteString
readProvisioningDescriptorRange descriptor offset requestedBytes = do
  let maximumRangeBytes =
        32 + fromIntegral maximumMachOLoadCommandBytes
      descriptorOffset = fromIntegral offset :: FileOffset
  unless
    ( offset >= 0
        && requestedBytes >= 0
        && requestedBytes <= maximumRangeBytes
        && fromIntegral descriptorOffset == offset
    )
    (ioError (userError "Mach-O metadata range exceeds its fixed bound"))
  observedOffset <- fdSeek descriptor AbsoluteSeek descriptorOffset
  unless
    (observedOffset == descriptorOffset)
    (ioError (userError "Mach-O metadata descriptor seek disagreed"))
  readExactly requestedBytes []
  where
    readExactly remaining chunks
      | remaining == 0 = pure (ByteString.concat (reverse chunks))
      | otherwise = do
          let chunkBytes = min remaining (64 * 1024)
          chunk <-
            readProvisioningDescriptorChunk
              descriptor
              (fromIntegral chunkBytes)
          when
            (ByteString.null chunk)
            (ioError (userError "Mach-O metadata range is truncated"))
          readExactly
            (remaining - fromIntegral (ByteString.length chunk))
            (chunk : chunks)

parseMachOInspection ::
  ByteString.ByteString ->
  Either String MachOInspection
parseMachOInspection contents
  | ByteString.take 4 contents == thinMachOMagic =
      parseThinMachO contents
  | ByteString.take 4 contents == fat32MachOMagic =
      selectFatMachOSlice False contents >>= parseThinMachO
  | ByteString.take 4 contents == fat64MachOMagic =
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
                      ( \dependency ->
                          resolveMachOFixtureDependency
                            images
                            imagePath
                            executableDirectory
                            localRpaths
                            ( dependency
                                `elem` machOOptionalDependencies inspection
                            )
                            dependency
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

-- | Resolve one fixture dependency the way the production closure does.
--
-- The optional flag is what keeps this fixture honest rather than merely
-- convenient. @dyld@ binds an unresolved @LC_LOAD_WEAK_DYLIB@ or
-- @LC_LAZY_LOAD_DYLIB@ to null at run time, so 'firstExistingMachOPath' skips
-- it and fails only on a required dependency. A fixture that treated every
-- unresolved install name as fatal would model a stricter resolver than the one
-- that ships, and the divergence would sit in exactly the direction that hides
-- a real closure gap.
resolveMachOFixtureDependency ::
  [(FilePath, ByteString.ByteString)] ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  Bool ->
  FilePath ->
  Either String [FilePath]
resolveMachOFixtureDependency
  images
  loaderPath
  executableDirectory
  rpaths
  dependencyIsOptional
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
        | dependencyIsOptional = Right []
        | otherwise =
            Left ("Mach-O fixture dependency is unresolved: " <> path)

      requireFirstFixtureImage candidates =
        case candidates of
          []
            | dependencyIsOptional -> Right []
            | otherwise ->
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
    && all
      (\component -> component /= "." && component /= "..")
      (splitDirectories path)

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
  (sliceOffset, sliceSize) <-
    selectFatMachOArm64Range is64 contents
  boundedByteStringSlice contents sliceOffset sliceSize

selectFatMachOArm64Range ::
  Bool ->
  ByteString.ByteString ->
  Either String (Word64, Word64)
selectFatMachOArm64Range is64 contents = do
  architectureCount <- readWord32BE contents 4
  unlessEither
    ( architectureCount > 0
        && architectureCount <= maximumFatArchitectures
    )
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
    [sliceRange] -> Right sliceRange
    [] -> Left "fat Mach-O has no arm64 slice"
    _ -> Left "fat Mach-O has ambiguous arm64 slices"

parseThinMachO ::
  ByteString.ByteString ->
  Either String MachOInspection
parseThinMachO contents = do
  unlessEither
    (ByteString.take 4 contents == thinMachOMagic)
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
    []
    0

walkCommands ::
  ByteString.ByteString ->
  Word32 ->
  Int ->
  Int ->
  [FilePath] ->
  [FilePath] ->
  [FilePath] ->
  Integer ->
  Either String MachOInspection
walkCommands contents commandsRemaining offset commandEnd dependencies optionalDependencies rpaths metadataBytes
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
            machOOptionalDependencies = List.nub (reverse optionalDependencies),
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
            ( if command `elem` machOOptionalDylibLoadCommands
                then value : optionalDependencies
                else optionalDependencies
            )
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
                optionalDependencies
                (value : rpaths)
                (metadataBytes + fromIntegral (length value))
            else
              walkCommands
                contents
                (commandsRemaining - 1)
                nextOffset
                commandEnd
                dependencies
                optionalDependencies
                rpaths
                metadataBytes

-- | Every load command that names a dependent dylib: @LC_LOAD_DYLIB@,
-- @LC_LOAD_WEAK_DYLIB@, @LC_LAZY_LOAD_DYLIB@, @LC_REEXPORT_DYLIB@, and
-- @LC_LOAD_UPWARD_DYLIB@.
machODylibLoadCommands :: [Word32]
machODylibLoadCommands =
  [ 0x0000000c,
    0x80000018,
    0x00000020,
    0x8000001f,
    0x80000023
  ]

-- | The dylib load commands @dyld@ allows to resolve to nothing:
-- @LC_LOAD_WEAK_DYLIB@ and @LC_LAZY_LOAD_DYLIB@.
machOOptionalDylibLoadCommands :: [Word32]
machOOptionalDylibLoadCommands =
  [ 0x80000018,
    0x00000020
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
      collapseMachORpath (takeDirectory loaderPath </> suffix)
  | rawPath == "@executable_path" =
      pure executableDirectory
  | Just suffix <- List.stripPrefix "@executable_path/" rawPath =
      collapseMachORpath (executableDirectory </> suffix)
  | isAbsolute rawPath = collapseMachORpath rawPath
  | otherwise =
      Left ("unsupported Mach-O LC_RPATH: " <> rawPath)

-- | Lexically collapse @.@ and @..@ in an expanded LC_RPATH. Both anchors
-- ('@loader_path'\/'@executable_path') are already canonical directories, so a
-- lexical collapse agrees with the kernel resolution the IO closure obtains
-- from 'Directory.canonicalizePath'; the pure fixture resolver has no
-- filesystem and must collapse the parent references itself.
collapseMachORpath :: FilePath -> Either String FilePath
collapseMachORpath rawPath
  | not (isAbsolute rawPath) =
      Left ("Mach-O LC_RPATH did not expand absolutely: " <> rawPath)
  | otherwise =
      case splitDirectories rawPath of
        root : components ->
          normalise . joinPath . (root :) . reverse
            <$> foldM collapseComponent [] components
        [] -> Left ("Mach-O LC_RPATH did not expand absolutely: " <> rawPath)
  where
    collapseComponent parents component
      | component == "." = Right parents
      | component /= ".." = Right (component : parents)
      | otherwise =
          case parents of
            _ : remaining -> Right remaining
            [] ->
              Left
                ("Mach-O LC_RPATH escapes its filesystem root: " <> rawPath)

resolveMachODependencies ::
  [FilePath] ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  [FilePath] ->
  [FilePath] ->
  IO [(FilePath, FilePath)]
resolveMachODependencies
  closureRoots
  loaderPath
  executableDirectory
  rpaths
  optionalDependencies
  dependencies =
    fmap
      concat
      ( mapM
          ( \dependency ->
              resolveMachODependency
                closureRoots
                loaderPath
                executableDirectory
                rpaths
                (dependency `elem` optionalDependencies)
                dependency
          )
          dependencies
      )

resolveMachODependency ::
  [FilePath] ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  Bool ->
  FilePath ->
  IO [(FilePath, FilePath)]
resolveMachODependency closureRoots loaderPath executableDirectory rpaths dependencyIsOptional dependency =
  do
    configuredPath <-
      if
        | isAbsolute dependency ->
            pure (Just dependency)
        | dependency == "@loader_path" ->
            pure (Just (takeDirectory loaderPath))
        | Just suffix <- List.stripPrefix "@loader_path/" dependency ->
            Just
              <$> anchoredMachOPath
                closureRoots
                loaderPath
                (takeDirectory loaderPath)
                suffix
                dependency
        | dependency == "@executable_path" ->
            pure (Just executableDirectory)
        | Just suffix <- List.stripPrefix "@executable_path/" dependency ->
            Just
              <$> anchoredMachOPath
                closureRoots
                loaderPath
                executableDirectory
                suffix
                dependency
        | Just suffix <- List.stripPrefix "@rpath/" dependency -> do
            safeSuffix <- requireSafeMachORelativeSuffix False suffix dependency
            firstExistingMachOPath
              [ rpath </> safeSuffix
              | rpath <- rpaths
              ]
              dependencyIsOptional
              ( dependency
                  <> " required by "
                  <> loaderPath
                  <> "; searched "
                  <> show rpaths
              )
        | otherwise ->
            ioError
              (userError ("unsupported Mach-O dependency install name: " <> dependency))
    case configuredPath of
      Nothing -> pure []
      Just resolvedPath -> do
        canonicalPath <- Directory.canonicalizePath resolvedPath
        unless
          (isAbsolute canonicalPath)
          (ioError (userError ("Mach-O dependency did not resolve absolutely: " <> dependency)))
        if systemMachOPath canonicalPath
          then pure []
          else
            pure
              [ (takeFileName dependency, canonicalPath)
              ]

-- | Anchor a relative install-name suffix to @\@loader_path@ or
-- @\@executable_path@.
--
-- A suffix that ascends through @..@ is admitted only when the anchoring image
-- lives inside one of the package closures being walked, and only when the
-- collapsed target stays inside that same closure. This is the layout every
-- delocated Python wheel uses -- NumPy, SciPy, and Pillow all load
-- @\@loader_path\/..\/.dylibs\/<name>@ -- so refusing it outright makes those
-- environments unvendorable. Confining the ascent to the closure keeps the
-- guarantee the flat ban provided: an install name still cannot reach out of
-- the environment and pull an arbitrary host library into the artifact. An
-- image outside every closure (a host CLI and its own runtime closure) keeps
-- the strict no-@..@ rule unchanged.
-- | Resolve one @\@loader_path@-anchored install name exactly as the closure
-- walk does, so the ascent policy can be asserted without a live materialization.
machOInstallNameTargetForTest ::
  [FilePath] ->
  FilePath ->
  FilePath ->
  IO (Either String FilePath)
machOInstallNameTargetForTest closureRoots loaderPath installName =
  case List.stripPrefix "@loader_path/" installName of
    Nothing ->
      pure (Left "fixture install name is not @loader_path-anchored")
    Just suffix -> do
      resolved <-
        try @IOException
          ( anchoredMachOPath
              closureRoots
              loaderPath
              (takeDirectory loaderPath)
              suffix
              installName
          )
      pure (either (Left . displayException) Right resolved)

anchoredMachOPath ::
  [FilePath] ->
  FilePath ->
  FilePath ->
  FilePath ->
  FilePath ->
  IO FilePath
anchoredMachOPath closureRoots loaderPath anchor suffix installName =
  case List.find (`writerPathWithin` loaderPath) closureRoots of
    Nothing -> do
      safeSuffix <- requireSafeMachORelativeSuffix False suffix installName
      pure (anchor </> safeSuffix)
    Just closureRoot -> do
      safeSuffix <- requireSafeMachORelativeSuffix True suffix installName
      collapsed <-
        either
          (ioError . userError)
          pure
          (collapseMachORpath (anchor </> safeSuffix))
      unless
        (closureRoot `writerPathWithin` collapsed)
        ( ioError
            ( userError
                ( "Mach-O install name escapes its package closure: "
                    <> installName
                    <> " resolved to "
                    <> collapsed
                    <> " outside "
                    <> closureRoot
                )
            )
        )
      pure collapsed

requireSafeMachORelativeSuffix ::
  Bool ->
  FilePath ->
  FilePath ->
  IO FilePath
requireSafeMachORelativeSuffix allowAscent suffix installName = do
  let components = splitDirectories suffix
  unless
    ( not (null suffix)
        && not (isAbsolute suffix)
        && '\NUL' `notElem` suffix
        && all
          ( \component ->
              (allowAscent || component /= "..")
                && component /= "."
                && component /= "/"
          )
          components
    )
    (ioError (userError ("Mach-O install name has an unsafe relative suffix: " <> installName)))
  pure suffix

-- | The first inherited @LC_RPATH@ candidate that exists.
--
-- A required dependency that no candidate resolves is fatal. A weak or lazy
-- dependency that no candidate resolves is absent by design — @dyld@ binds it
-- to null at run time — so it contributes nothing to the closure instead.
firstExistingMachOPath ::
  [FilePath] ->
  Bool ->
  FilePath ->
  IO (Maybe FilePath)
firstExistingMachOPath candidates dependencyIsOptional dependency =
  case candidates of
    []
      | dependencyIsOptional -> pure Nothing
      | otherwise ->
          ioError
            (userError ("no inherited LC_RPATH resolves dependency " <> dependency))
    candidate : remaining -> do
      status <- try @IOException (Posix.getSymbolicLinkStatus candidate)
      case status of
        Right observed
          | Posix.isRegularFile observed
              || Posix.isSymbolicLink observed ->
              pure (Just candidate)
        _ -> firstExistingMachOPath remaining dependencyIsOptional dependency

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
resolvePackageClosureIdentity =
  resolvePackageClosureIdentityFor RetainedPackageClosureIdentity

-- | Whether a closure identity is being minted from its retained external
-- source or from the already-filtered copy. The source identity omits the
-- Python-home entries that cannot be sealed; the copy must hash every entry
-- that remains so reinjection cannot hide behind the source exclusion policy.
data PackageClosureIdentityTarget
  = RetainedPackageClosureIdentity
  | SealedPackageClosureIdentity
  deriving (Eq, Show)

resolvePackageClosureIdentityFor ::
  PackageClosureIdentityTarget ->
  Internal.ProvisioningPackageClosureRole ->
  FilePath ->
  IO Internal.ProvisioningPackageClosureIdentity
resolvePackageClosureIdentityFor verificationTarget role closureRoot =
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
                ( verificationTarget == RetainedPackageClosureIdentity
                    && role == Internal.ProvisioningPythonHomeClosure
                )
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

-- | The package-closure byte bound.
--
-- Chosen against measurement, not raised to unblock one. The scanned source
-- closure of a PyTorch-class environment is what is large here, not the sealed
-- artifact: the largest measured activated artifact, @coreml-native@, is
-- 1.353 GiB across 35,260 entries, while its scanned source venv plus Python
-- home closure is several times that. 12 GiB holds it with room for one more
-- PyTorch major without becoming an unbounded scan.
--
-- All seven artifacts are now measured from one materialization that
-- pre-extracts the JavaCPP natives into the sealed payload, which is the
-- condition that previously left @jvm-native@ provisional. Activated payload
-- bytes and entries: @coreml-native@ 1452756350 \/ 35260, @mlx-native@
-- 380423504 \/ 9477, @ctranslate2-native@ 262042645 \/ 7285,
-- @onnx-runtime-native@ 253792784 \/ 7510, @jvm-native@ 146358899 \/ 2806,
-- @llama-cpp-cli@ 19578868 \/ 24, @whisper-cpp-cli@ 4956903 \/ 19.
maximumPoetryClosureBytes :: Integer
maximumPoetryClosureBytes = 12 * 1024 * 1024 * 1024

-- | The package-closure entry bound. @coreml-native@ measures 35,260 entries,
-- the largest of the seven artifacts; the next largest, @mlx-native@, is 9,477.
maximumPoetryClosureFiles :: Integer
maximumPoetryClosureFiles = 100000

-- | Which dimension of the closure bounds a fold is reporting on.
--
-- The bounds these name are otherwise unreachable from any gate. The precedent
-- is 'maximumRelocationCandidateBytes', which exports both an accessor and a
-- pure fold and is covered positively and on overflow: a bound with no pure
-- validator is a bound no gate can regress.
data ProvisioningClosureBound
  = PoetryClosureBytesBound
  | PoetryClosureFilesBound
  | ExactRuntimeFileBytesBound
  | StableCopyBytesBound
  | MachOInspectionBytesBound
  | MachORuntimeBytesBound
  deriving (Eq, Show)

provisioningClosureBoundForTest :: ProvisioningClosureBound -> Integer
provisioningClosureBoundForTest bound =
  case bound of
    PoetryClosureBytesBound -> maximumPoetryClosureBytes
    PoetryClosureFilesBound -> maximumPoetryClosureFiles
    ExactRuntimeFileBytesBound -> maximumExactRuntimeFileBytes
    StableCopyBytesBound -> maximumStableCopyBytes
    MachOInspectionBytesBound -> maximumMachOInspectionBytes
    MachORuntimeBytesBound -> maximumMachORuntimeBytes

-- | Admit one regular file into a package closure.
--
-- Production and the covering test share this fold, so the assertion constrains
-- the code the materializer runs rather than a parallel restatement of it.
admitPackageClosureFile ::
  (Integer, Integer) ->
  Integer ->
  Either String (Integer, Integer)
admitPackageClosureFile totals fileBytes
  | fileBytes > maximumExactRuntimeFileBytes =
      Left
        ( "package closure entry exceeds its exact runtime file bound: "
            <> show fileBytes
            <> " > "
            <> show maximumExactRuntimeFileBytes
        )
  | otherwise = admitPackageClosureTotals totals fileBytes

-- | Admit one closure entry's contribution to the running totals. A link's
-- target string has no per-entry byte bound of its own; its containment rule is
-- 'validRelativeClosureLink', applied at its own site.
admitPackageClosureTotals ::
  (Integer, Integer) ->
  Integer ->
  Either String (Integer, Integer)
admitPackageClosureTotals (bytes, files) entryBytes
  | entryBytes < 0 =
      Left "package closure entry byte count must not be negative"
  | nextBytes > maximumPoetryClosureBytes =
      Left
        ( "package closure exceeds its byte bound: "
            <> show nextBytes
            <> " > "
            <> show maximumPoetryClosureBytes
        )
  | nextFiles > maximumPoetryClosureFiles =
      Left
        ( "package closure exceeds its entry bound: "
            <> show nextFiles
            <> " > "
            <> show maximumPoetryClosureFiles
        )
  | otherwise = Right (nextBytes, nextFiles)
  where
    nextBytes = bytes + entryBytes
    nextFiles = files + 1

admitPackageClosureFileForTest ::
  (Integer, Integer) ->
  Integer ->
  Either String (Integer, Integer)
admitPackageClosureFileForTest = admitPackageClosureFile

admitPackageClosureTotalsForTest ::
  (Integer, Integer) ->
  Integer ->
  Either String (Integer, Integer)
admitPackageClosureTotalsForTest = admitPackageClosureTotals

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
      directoryContext `seq`
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
              ( do
                  status <- Posix.getFdStatus descriptor
                  unless
                    (Posix.isRegularFile status)
                    (ioError (userError ("Poetry closure entry is not a regular file: " <> path)))
                  excluded <-
                    excludedPythonHomeShebangFile
                      excludeBaseSitePackages
                      closureRoot
                      relativePath
                      descriptor
                  if excluded
                    then do
                      recheckRetainedPackageClosureFile
                        parentDescriptor
                        entry
                        path
                        descriptor
                        status
                      pure state
                    else
                      digestPackageClosureFile
                        parentDescriptor
                        entry
                        path
                        descriptor
                        relativePath
                        state
              )
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
    (nextBytes, nextFiles) <-
      either
        (\failure -> ioError (userError (failure <> ": " <> path)))
        pure
        ( admitPackageClosureFile
            (closureBytes state, closureFiles state)
            fileBytes
        )
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
    context `seq` pure (nextBytes, nextFiles, context)

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
        unless
          (validRelativeClosureLink relativePath linkTarget)
          (ioError (userError ("Poetry package closure has an unsafe link: " <> path)))
        (nextBytes, nextFiles) <-
          either
            (\failure -> ioError (userError (failure <> ": " <> path)))
            pure
            ( admitPackageClosureTotals
                (closureBytes state, closureFiles state)
                linkBytes
            )
        let nextContext =
              updateClosureDigest
                (closureDigestContext state)
                ( "L\NUL"
                    <> relativePath
                    <> "\NUL"
                    <> linkTarget
                    <> "\NUL"
                )
        nextContext `seq` pure (nextBytes, nextFiles, nextContext)

validRelativeClosureLink :: FilePath -> FilePath -> Bool
validRelativeClosureLink relativePath linkTarget =
  not (isAbsolute linkTarget)
    && '\NUL' `notElem` linkTarget
    && case splitDirectories
      (normalise (takeDirectory relativePath </> linkTarget)) of
      ".." : _ -> False
      _ -> True

validRelativeClosureLinkForTest :: FilePath -> FilePath -> Bool
validRelativeClosureLinkForTest = validRelativeClosureLink

excludedPythonBaseSitePackagesLink :: FilePath -> Bool
excludedPythonBaseSitePackagesLink relativePath =
  case splitDirectories (normalise relativePath) of
    ["lib", pythonDirectory, "site-packages"] ->
      "python" `List.isPrefixOf` pythonDirectory
    _ -> False

-- | Whether a file in a host Python home is an unsealable launcher.
--
-- Console scripts below @bin@ are excluded when their absolute shebang binds
-- any host installation, preserving the historical rule. CPython also emits
-- @lib\/pythonX.Y\/config-X.Y-\<plat\>\/python-config.py@ outside @bin@ with a
-- shebang naming the exact source Python home's @bin\/pythonX.Y@; that generated
-- launcher is excluded by the same binding.
--
-- Location alone and a blanket absolute-shebang rule are both too broad:
-- importable stdlib files such as @lib\/pythonX.Y\/cgi.py@ can carry
-- @#!\/usr\/local\/bin\/python@, and other stdlib tooling can carry @#!\/bin\/sh@.
-- Outside @bin@ those files remain unless the parsed interpreter is the exact
-- closure root's immediate @bin\/python*@ child. Portable @#! \/usr\/bin\/env
-- python3@ files remain everywhere.
--
-- A selected launcher cannot become part of a sealed artifact: running it
-- would exec the host interpreter and escape the generation. Rewriting is not
-- robust across substrate shebang limits, so exclusion removes the failure
-- mode rather than relocating it. Interpreter binaries resolved through
-- @pyvenv.cfg@ are not shebang files and are unaffected.
--
-- The retained-source digest and copy walks share this predicate. The copied
-- destination is then verified in sealed mode with no exclusions, so its
-- complete physical payload must equal that filtered source identity.
excludedPythonHomeShebangFile :: Bool -> FilePath -> FilePath -> Fd -> IO Bool
excludedPythonHomeShebangFile
  excludePythonHomeHostBindings
  closureRoot
  relativePath
  descriptor
    | not excludePythonHomeHostBindings = pure False
    | otherwise = do
        _ <- fdSeek descriptor AbsoluteSeek 0
        leading <-
          readProvisioningDescriptorPrefix
            descriptor
            maximumShebangProbeBytes
        _ <- fdSeek descriptor AbsoluteSeek 0
        pure
          ( pythonHomeClosureFileExcluded
              excludePythonHomeHostBindings
              closureRoot
              relativePath
              leading
          )

-- | Classify Python-home launchers from their relative position, parsed
-- interpreter, and the exact retained closure root.
pythonHomeClosureFileExcluded ::
  Bool ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Bool
pythonHomeClosureFileExcluded
  excludePythonHomeHostBindings
  closureRoot
  relativePath
  leading =
    excludePythonHomeHostBindings
      && shebangBindsHostInstallation leading
      && ( pythonHomeBinEntry relativePath
             || shebangBindsExactPythonHome closureRoot leading
         )

pythonHomeClosureFileExcludedForTest ::
  Bool ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Bool
pythonHomeClosureFileExcludedForTest = pythonHomeClosureFileExcluded

-- | The fixed prefix examined when classifying a shebang. It covers the
-- supported substrate parser limits without allowing a whole-file read.
maximumShebangProbeBytes :: ByteCount
maximumShebangProbeBytes = 512

-- | A shebang binds a host installation when it names an absolute interpreter
-- other than the portable @\/usr\/bin\/env@ launcher.
shebangBindsHostInstallation :: ByteString.ByteString -> Bool
shebangBindsHostInstallation leading =
  case shebangInterpreterPath leading of
    Just interpreterPath ->
      isAbsolute interpreterPath
        && normalise interpreterPath /= portableEnvLauncher
    Nothing -> False

-- | Parse only the interpreter token. Arguments following it are irrelevant
-- to whether the file is tied to a particular installation.
shebangInterpreterPath :: ByteString.ByteString -> Maybe FilePath
shebangInterpreterPath leading =
  case ByteString.stripPrefix (ByteString.pack [0x23, 0x21]) leading of
    Nothing -> Nothing
    Just afterMarker ->
      case ByteString8.words (ByteString8.takeWhile (/= '\n') afterMarker) of
        interpreter : _ -> Just (ByteString8.unpack interpreter)
        [] -> Nothing

-- | Preserve the historical console-script rule under @bin@. Outside that
-- subtree, omit only a launcher whose interpreter is the exact Python home's
-- immediate @bin/python*@ executable. This catches CPython's generated
-- @lib/pythonX.Y/config-.../python-config.py@ without deleting importable
-- stdlib files that happen to carry @/usr/local/bin/python@ or @/bin/sh@.
pythonHomeBinEntry :: FilePath -> Bool
pythonHomeBinEntry relativePath =
  case splitDirectories (normalise relativePath) of
    "bin" : _ -> True
    _ -> False

shebangBindsExactPythonHome :: FilePath -> ByteString.ByteString -> Bool
shebangBindsExactPythonHome closureRoot leading =
  case shebangInterpreterPath leading of
    Just interpreterPath ->
      isAbsolute interpreterPath
        && '\NUL' `notElem` interpreterPath
        && normalise interpreterPath == interpreterPath
        && normalise (takeDirectory interpreterPath)
          == normalise (closureRoot </> "bin")
        && "python" `List.isPrefixOf` takeFileName interpreterPath
    Nothing -> False

-- | The one absolute shebang interpreter that names no installation.
portableEnvLauncher :: FilePath
portableEnvLauncher = "/usr/bin/env"

-- | Classify a file's leading bytes exactly as the Python home closure does.
shebangBindsHostInstallationForTest :: ByteString.ByteString -> Bool
shebangBindsHostInstallationForTest = shebangBindsHostInstallation

-- | Classify a file's leading header exactly as the Mach-O closure scan does.
supportedMachOMagicForTest :: ByteString.ByteString -> Bool
supportedMachOMagicForTest = supportedMachOMagic

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
      destinationComponents <-
        authorizedWriterRelativeComponents
          "fixed runtime closure destination"
          authorizedRoot
          destination
      prepareEmptyClosureDestination authorizedRoot destination
      let source =
            Internal.provisioningPackageClosureRoot expectedSource
          role =
            Internal.provisioningPackageClosureRole expectedSource
          context =
            PackageClosureCopyContext
              { closureCopyExcludeBaseSitePackages =
                  role == Internal.ProvisioningPythonHomeClosure,
                closureCopySourceRoot = source,
                closureCopyWriterRoot = authorizedRoot
              }
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
            copiedEntries <-
              withRetainedClosureDestination
                authorizedRoot
                destination
                ( \destinationDescriptor ->
                    copyPackageClosureDirectory
                      context
                      source
                      destination
                      destinationComponents
                      sourceDescriptor
                      destinationDescriptor
                      openedSourceStatus
                      "."
                      0
                      0
                )
            unless
              (copiedEntries <= maximumPoetryClosureFiles)
              (ioError (userError "fixed runtime closure copy exceeded its entry bound"))
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
      installed <-
        resolvePackageClosureIdentityFor
          SealedPackageClosureIdentity
          role
          destination
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

-- | Ensure a package-closure destination exists and is stably empty.
--
-- Creation goes through the mutation kernel and the emptiness proof is taken
-- through the retained parent descriptor, so neither step re-resolves the
-- destination pathname.
prepareEmptyClosureDestination ::
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
prepareEmptyClosureDestination authorizedRoot destination = do
  observed <-
    observeAuthorizedPathStatus
      "fixed runtime closure destination"
      authorizedRoot
      destination
  case observed of
    Nothing ->
      ensureAuthorizedDirectoryTree
        "fixed runtime closure destination"
        authorizedRoot
        destination
    Just listedStatus ->
      unless
        ( Posix.isDirectory listedStatus
            && not (Posix.isSymbolicLink listedStatus)
        )
        (ioError (userError "fixed runtime closure destination is not a real directory"))
  withRetainedClosureDestination
    authorizedRoot
    destination
    ( \descriptor -> do
        openedStatus <- Posix.getFdStatus descriptor
        entries <- listDirectoryBoundedFromDescriptor descriptor 1
        finalStatus <- Posix.getFdStatus descriptor
        unless
          ( null entries
              && stableExecutableStatus openedStatus finalStatus
          )
          (ioError (userError "fixed runtime closure destination is not stably empty"))
    )

-- | Retain a descriptor on a directory inside an authorized writer root, reached
-- through that root's retained ancestry rather than by re-resolving its
-- pathname.
--
-- This is the entry point for every traversal whose interior is already
-- descriptor-anchored: it replaces the single full-path @openFd@ that made the
-- root of such a traversal swappable while everything below it was safe.
withRetainedAuthorizedDirectory ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  (Fd -> IO result) ->
  IO result
withRetainedAuthorizedDirectory label authorizedRoot directory action =
  withAuthorizedLeafParent
    label
    authorizedRoot
    directory
    ( \parentDescriptor leaf -> do
        descriptor <-
          openFdAt
            (Just parentDescriptor)
            leaf
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                directory = True,
                cloexec = True
              }
        finallyPreservingPrimary
          ( do
              status <- Posix.getFdStatus descriptor
              unless
                (Posix.isDirectory status)
                (ioError (userError (label <> " is not a directory")))
              result <- action descriptor
              finalStatus <- Posix.getFdStatus descriptor
              unless
                (sameFileObject status finalStatus)
                (ioError (userError (label <> " changed during traversal")))
              pure result
          )
          (closeFd descriptor)
    )

-- | The closure destination's retained directory descriptor.
withRetainedClosureDestination ::
  AuthorizedWriterRoot ->
  FilePath ->
  (Fd -> IO result) ->
  IO result
withRetainedClosureDestination =
  withRetainedAuthorizedDirectory "fixed runtime closure destination"

-- | The context a package-closure copy carries unchanged down its recursion.
data PackageClosureCopyContext = PackageClosureCopyContext
  { closureCopyExcludeBaseSitePackages :: !Bool,
    closureCopySourceRoot :: !FilePath,
    closureCopyWriterRoot :: !AuthorizedWriterRoot
  }

copyPackageClosureDirectory ::
  PackageClosureCopyContext ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  Fd ->
  Fd ->
  Posix.FileStatus ->
  FilePath ->
  Int ->
  Integer ->
  IO Integer
copyPackageClosureDirectory
  context
  sourceDirectory
  destinationDirectory
  destinationComponents
  sourceDescriptor
  destinationDescriptor
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
            context
            sourceDirectory
            destinationDirectory
            destinationComponents
            sourceDescriptor
            destinationDescriptor
            relativeDirectory
            depth
        )
        entriesSeen
        entries
    finalSourceStatus <- Posix.getFdStatus sourceDescriptor
    unless
      (stableExecutableStatus listedSourceStatus finalSourceStatus)
      (ioError (userError "fixed runtime closure directory changed during copy"))
    synchroniseProvisioningDescriptor destinationDescriptor
    pure finalEntries

copyPackageClosureEntry ::
  PackageClosureCopyContext ->
  FilePath ->
  FilePath ->
  [FilePath] ->
  Fd ->
  Fd ->
  FilePath ->
  Int ->
  Integer ->
  FilePath ->
  IO Integer
copyPackageClosureEntry
  context
  sourceDirectory
  destinationDirectory
  destinationComponents
  sourceParentDescriptor
  destinationParentDescriptor
  parentRelative
  parentDepth
  entriesSeen
  entry = do
    let excludeBaseSitePackages = closureCopyExcludeBaseSitePackages context
        authorizedRoot = closureCopyWriterRoot context
        source = sourceDirectory </> entry
        destination = destinationDirectory </> entry
        entryComponents = destinationComponents <> [entry]
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
              runAuthorizedFilesystemMutation
                "fixed runtime closure directory"
                authorizedRoot
                ( Subprocess.provisioningCreateDirectoryLeaf
                    (authorizedWriterMutationRoot authorizedRoot)
                    destinationComponents
                    entry
                )
              copied <-
                withRetainedClosureChildDirectory
                  destinationParentDescriptor
                  entry
                  ( \destinationChildDescriptor ->
                      copyPackageClosureDirectory
                        context
                        source
                        destination
                        entryComponents
                        childDescriptor
                        destinationChildDescriptor
                        childStatus
                        relativePath
                        (parentDepth + 1)
                        nextEntries
                  )
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
                  excluded <-
                    excludedPythonHomeShebangFile
                      excludeBaseSitePackages
                      (closureCopySourceRoot context)
                      relativePath
                      sourceFileDescriptor
                  unless excluded $ do
                    _ <-
                      copyRegularFileStableIntoRetainedParent
                        ( StableCopySourceRetainedDescriptor
                            sourceFileDescriptor
                            sourceFileStatus
                            ( recheckRetainedPackageClosureFile
                                sourceParentDescriptor
                                entry
                                source
                                sourceFileDescriptor
                                sourceFileStatus
                            )
                        )
                        authorizedRoot
                        destinationParentDescriptor
                        entry
                        maximumExactRuntimeFileBytes
                        source
                        destination
                    pure ()
                  recheckRetainedPackageClosureFile
                    sourceParentDescriptor
                    entry
                    source
                    sourceFileDescriptor
                    sourceFileStatus
                  pure (if excluded then entriesSeen else nextEntries)
              )
              (closeFd sourceFileDescriptor)
          Left _ ->
            copyPackageClosureLink
              context
              sourceParentDescriptor
              destinationComponents
              entry
              sourceDirectory
              source
              relativePath
              nextEntries

-- | Retain a descriptor on a freshly created closure child directory, reached
-- through the parent descriptor the recursion already holds.
withRetainedClosureChildDirectory ::
  Fd ->
  FilePath ->
  (Fd -> IO result) ->
  IO result
withRetainedClosureChildDirectory parentDescriptor entry action = do
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
    ( do
        status <- Posix.getFdStatus descriptor
        unless
          (Posix.isDirectory status)
          (ioError (userError "fixed runtime closure child destination is not a directory"))
        action descriptor
    )
    (closeFd descriptor)

copyPackageClosureLink ::
  PackageClosureCopyContext ->
  Fd ->
  [FilePath] ->
  FilePath ->
  FilePath ->
  FilePath ->
  FilePath ->
  Integer ->
  IO Integer
copyPackageClosureLink
  context
  sourceParentDescriptor
  destinationComponents
  entry
  sourceParent
  source
  relativePath
  nextEntries = do
    let excludeBaseSitePackages = closureCopyExcludeBaseSitePackages context
        authorizedRoot = closureCopyWriterRoot context
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
        -- The kernel creates the link with the retained parent as its working
        -- directory, then reads it back and requires the recorded target before
        -- fsyncing that parent. That read-back is the installed-link
        -- confirmation, and it is the only one available: a symbolic link cannot
        -- be opened @O_NOFOLLOW@ in process, so any parent-side re-read would
        -- have to re-resolve the destination pathname -- exactly the effect this
        -- conversion removes.
        runAuthorizedFilesystemMutation
          "fixed runtime closure link"
          authorizedRoot
          ( Subprocess.provisioningCreateSymbolicLinkLeaf
              (authorizedWriterMutationRoot authorizedRoot)
              destinationComponents
              entry
              target
          )
        finalSourceStatus <- Posix.getSymbolicLinkStatus source
        finalSourceTarget <- Posix.readSymbolicLink source
        finalParentStatus <- Posix.getFdStatus sourceParentDescriptor
        finalParentPathStatus <- Posix.getSymbolicLinkStatus sourceParent
        unless
          ( stableExecutableStatus sourceStatus finalSourceStatus
              && finalSourceTarget == target
              && stableExecutableStatus parentStatus finalParentStatus
              && stableExecutableStatus finalParentStatus finalParentPathStatus
          )
          (ioError (userError "fixed runtime closure link changed during copy"))
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
  -- The containment check above is what this function adds: the requested
  -- directory must lie under the /candidate/ root, not merely under the writer
  -- root. Creation itself is delegated, because the superseded per-component
  -- loop was a weaker duplicate of 'ensureAuthorizedDirectoryTree' -- it created
  -- and fsynced each component by pathname, while the retained form observes
  -- each level through the writer root's descriptor and creates it through the
  -- mutation kernel.
  case writer of
    EngineWriter _ _ writerRoot ->
      ProvisioningSession
        ( ensureAuthorizedDirectoryTree
            "fixed runtime directory"
            writerRoot
            authorizedDirectory
        )

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
      linkComponents <-
        authorizedWriterRelativeComponents
          "fixed runtime link"
          authorizedRoot
          link
      let relativeLink =
            makeRelative
              (authorizedWriterCanonicalRoot authorizedRoot)
              link
      unless
        (validRelativeClosureLink relativeLink target)
        (ioError (userError "fixed runtime link escapes its artifact root"))
      -- The kernel creates the link with the retained parent as its working
      -- directory and confirms the recorded target before fsyncing that parent,
      -- which is the only descriptor-anchored link creation available: there is
      -- no public @symlinkat@, and a symbolic link cannot be opened
      -- @O_NOFOLLOW@ for a parent-side re-read.
      runAuthorizedFilesystemMutation
        "fixed runtime link"
        authorizedRoot
        ( Subprocess.provisioningCreateSymbolicLinkLeaf
            (authorizedWriterMutationRoot authorizedRoot)
            (init linkComponents)
            (last linkComponents)
            target
        )
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
        (resolvedExecutableCanonicalIdentityMatches expected observed)
        (ioError (userError "fixed executable source changed before copy"))
      copied <-
        copyRegularFileStable
          ( StableCopySourceExactContent
              (resolvedExecutableDigest expected)
          )
          authorizedRoot
          maximumExactRuntimeFileBytes
          (resolvedExecutableCanonicalPath expected)
          destination
      finalObserved <-
        resolveExactExecutableIdentity
          (resolvedExecutableCanonicalPath expected)
      unless
        ( resolvedExecutableCanonicalIdentityMatches expected finalObserved
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
          ( StableCopySourceExactContent
              (Internal.provisioningRuntimeLibraryDigest expected)
          )
          authorizedRoot
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
        List.foldl'
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

recheckRetainedPackageClosureFile ::
  Fd ->
  FilePath ->
  FilePath ->
  Fd ->
  Posix.FileStatus ->
  IO ()
recheckRetainedPackageClosureFile
  sourceParentDescriptor
  entry
  source
  sourceFileDescriptor
  sourceFileStatus = do
    finalStatus <- Posix.getFdStatus sourceFileDescriptor
    reopenedStatus <- reopenFileEntryStatus sourceParentDescriptor entry
    unless
      ( stableExecutableStatus sourceFileStatus finalStatus
          && stableExecutableStatus finalStatus reopenedStatus
      )
      (ioError (userError ("stable copy source changed while copying: " <> source)))

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
          chunk <- readProvisioningDescriptorChunk descriptor requested
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
                  nextContext = SHA256.update context chunk
              unless
                (nextBytes <= expectedBytes)
                (ioError (userError "package descriptor grew beyond its exact byte bound"))
              -- 'SHA256.update' is pure but defers its descriptor-chunk work
              -- until the resulting context is demanded. Force every step so
              -- a large file cannot remain live as a chain of chunk thunks.
              nextContext `seq` go nextBytes nextContext

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
          chunk <- readProvisioningDescriptorChunk descriptor requested
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
  pure (flattenCaughtProvisioningFailure result)

-- | A real directory, never a symlink to one.
realDirectoryStatus :: Posix.FileStatus -> Bool
realDirectoryStatus status =
  Posix.isDirectory status && not (Posix.isSymbolicLink status)

-- | A real regular file, never a symlink to one.
realRegularFileStatus :: Posix.FileStatus -> Bool
realRegularFileStatus status =
  Posix.isRegularFile status && not (Posix.isSymbolicLink status)

-- | A regular file carrying at least one execute bit.
executableRegularFileStatus :: Posix.FileStatus -> Bool
executableRegularFileStatus status =
  Posix.isRegularFile status
    && Posix.fileMode status
      .&. ( Posix.ownerExecuteMode
              .|. Posix.groupExecuteMode
              .|. Posix.otherExecuteMode
          )
      /= 0

-- | Fold a caught provisioning failure into its rendered error string.
displayCaughtProvisioningFailure ::
  Either IOException value ->
  Either String value
displayCaughtProvisioningFailure caught =
  case caught of
    Left failure -> Left (displayException failure)
    Right value -> Right value

-- | Fold a caught provisioning failure into an already-classified result.
flattenCaughtProvisioningFailure ::
  Either IOException (Either String value) ->
  Either String value
flattenCaughtProvisioningFailure caught =
  case caught of
    Left failure -> Left (displayException failure)
    Right value -> value

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

-- | Read one chunk from a descriptor, mapping end-of-file to an empty result.
--
-- 'PosixByteString.fdRead' throws an EOF 'IOError' at end of file rather than
-- returning an empty 'ByteString', so every loop below — each of which reads
-- one byte past the declared size to detect growth — must translate that throw
-- into the ordinary end-of-stream it is written against.
readProvisioningDescriptorChunk ::
  Fd ->
  ByteCount ->
  IO ByteString.ByteString
readProvisioningDescriptorChunk descriptor requested = do
  observed <-
    try @IOException (PosixByteString.fdRead descriptor requested)
  case observed of
    Right chunk -> pure chunk
    Left failure
      | isEOFError failure -> pure ByteString.empty
      | otherwise -> ioError failure

-- | Read a regular-file prefix through bounded requests. A successful POSIX
-- read may legally return fewer bytes than requested, so classification must
-- continue to the cap or EOF rather than treating one short read as the whole
-- prefix.
readProvisioningDescriptorPrefix ::
  Fd ->
  ByteCount ->
  IO ByteString.ByteString
readProvisioningDescriptorPrefix descriptor maximumBytes =
  go maximumBytes []
  where
    go remaining chunks
      | remaining == 0 = pure (ByteString.concat (reverse chunks))
      | otherwise = do
          chunk <- readProvisioningDescriptorChunk descriptor remaining
          if ByteString.null chunk
            then pure (ByteString.concat (reverse chunks))
            else
              go
                (remaining - fromIntegral (ByteString.length chunk))
                (chunk : chunks)

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
    else do
      let nextContext = SHA256.update digestContext chunk
      nextContext `seq` hashExecutableDescriptor nextContext descriptor

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
  outputLines <-
    exactRuntimeOutputLines (withoutAudiverisBannerTerminator adapter output)
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

-- | Read llama.cpp's exact build provenance out of the runner's diagnostics.
--
-- The sealed artifact sets @GGML_BACKEND_PATH@, so ggml reports each backend it
-- loads on stderr before the version banner. Those lines are legitimate runner
-- output, so the banner is located rather than assumed to stand alone. Exactly
-- one @version:@ line must appear and the line immediately after it must be the
-- build-provenance line, so an ambiguous or truncated banner still fails.
parseLlamaRuntimeVersion :: [Text] -> Either String Text
parseLlamaRuntimeVersion outputLines =
  case break (Text.isPrefixOf "version: ") outputLines of
    (_, versionLine : buildLine : remaining)
      | not (any (Text.isPrefixOf "version: ") remaining) ->
          parseLlamaVersionPair versionLine buildLine
    _ ->
      Left "llama-completion smoke did not emit exactly one version and build-provenance line pair"

parseLlamaVersionPair :: Text -> Text -> Either String Text
parseLlamaVersionPair versionLine buildLine = do
  payload <-
    maybe
      (Left "llama-completion smoke omitted its exact version line")
      Right
      (Text.stripPrefix "version: " versionLine)
  unlessEither
    ( maybe
        False
        validLlamaBuildProvenance
        (Text.stripPrefix "built with " buildLine)
    )
    "llama-completion smoke has an invalid build-provenance line"
  case Text.words payload of
    [build, parenthesizedHash] -> do
      commit <-
        maybe
          (Left "llama-completion smoke version has an invalid commit hash")
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
        "llama-completion smoke version has an invalid build or commit"
      pure ("llama.cpp-b" <> build <> "-" <> commit)
    _ ->
      Left "llama-completion smoke version has an invalid token cardinality"

-- | As with llama.cpp, whisper.cpp reports each ggml backend it loads before
-- its version banner, so exactly one banner line is located within the runner's
-- diagnostics rather than assumed to be the only line.
parseWhisperRuntimeVersion :: [Text] -> Either String Text
parseWhisperRuntimeVersion outputLines =
  case filter (Text.isPrefixOf whisperVersionPrefix) outputLines of
    [versionLine] -> do
      version <-
        maybe
          (Left "whisper-cli smoke omitted its exact version line")
          Right
          (Text.stripPrefix whisperVersionPrefix versionLine)
      unlessEither
        (validVersionAtom version)
        "whisper-cli smoke emitted an invalid version"
      pure version
    _ ->
      Left "whisper-cli smoke did not emit exactly one version line"

whisperVersionPrefix :: Text
whisperVersionPrefix = "whisper.cpp version: "

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

-- | Drop the one blank line Audiveris prints after its version banner.
--
-- The shared rule is that a smoke emits no empty line at all, because an empty
-- line is how junk gets carried past a field parser. Audiveris nonetheless
-- terminates @-version@ with @\\n\\n@. That is a fact about the upstream tool,
-- not a reason to relax the rule for the other six targets, so exactly one
-- trailing blank line is removed for exactly that adapter before the strict
-- check runs. A second blank line, a blank line anywhere else, and a blank
-- terminator on any other adapter all still fail closed.
withoutAudiverisBannerTerminator ::
  Internal.AppleAdapterId ->
  Text ->
  Text
withoutAudiverisBannerTerminator adapter output =
  case adapter of
    Internal.JvmAdapter
      | "\n\n" `Text.isSuffixOf` output -> Text.dropEnd 1 output
    _ -> output

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
  writer@(EngineWriter authority recovered authorizedRoot)
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
                authorizedRoot
                revalidated
          )
      published <-
        maybe
          (ioError (userError "Linux artifact generation is in use before publication"))
          pure
          publication
      activateLinuxCompletionState
        authority
        (provisioningArtifactRootMutator writer)
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
    let (enginesRoot, _, _, _) =
          artifactGenerationLeaseFields proposedLease
    siblingLeases <-
      retainedSiblingArtifactGenerationLeases
        enginesRoot
        installRoot
    mapM_
      ( \siblingLease -> do
          minted <-
            withTryArtifactGenerationMutationLock
              authority
              siblingLease
              (const (pure ()))
          unless (isJust minted) $
            ioError (userError "installed sibling generation lease is contended")
      )
      siblingLeases
    currentManifestExists <-
      Directory.doesFileExist
        (Artifact.engineArtifactManifestPath installRoot)
    if not currentManifestExists
      then
        reconcileObsoleteArtifactGenerationLeases
          authority
          (proposedLease : siblingLeases)
      else do
        currentManifestResult <-
          try @IOException
            ( ArtifactInternal.validateRetainedEngineArtifactRootAt
                installRoot
                installRoot
            )
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
              ( siblingLeases
                  <> ( if currentLease == proposedLease
                         then [proposedLease]
                         else [proposedLease, currentLease]
                     )
              )

-- Reconciliation is scoped to the shared engines root, so every installed
-- sibling generation must be retained while one adapter is replaced. Omitting
-- these leases makes each materialization retire the preceding adapters'
-- sidecars and leaves only the last artifact launchable.
retainedSiblingArtifactGenerationLeases ::
  FilePath ->
  FilePath ->
  IO [ArtifactGenerationLease]
retainedSiblingArtifactGenerationLeases enginesRoot installRoot = do
  entries <- List.sort <$> Directory.listDirectory enginesRoot
  unless (length entries <= 64) $
    ioError (userError "engine root exceeds the bounded sibling-artifact census")
  catMaybes
    <$> mapM
      ( \entry -> do
          let siblingRoot = enginesRoot </> entry
          isSiblingDirectory <- Directory.doesDirectoryExist siblingRoot
          manifestExists <-
            Directory.doesFileExist
              (Artifact.engineArtifactManifestPath siblingRoot)
          if siblingRoot == installRoot || not isSiblingDirectory || not manifestExists
            then pure Nothing
            else do
              manifest <-
                ArtifactInternal.validateRetainedEngineArtifactRootAt
                  siblingRoot
                  siblingRoot
              siblingIdentity <-
                maybe
                  ( ioError
                      (userError "installed sibling artifact has an unknown adapter identity")
                  )
                  pure
                  (ArtifactIdentity.parseNativeArtifactIdentity (Artifact.manifestAdapterId manifest))
              unless
                (entry == Text.unpack (Artifact.manifestAdapterId manifest))
                (ioError (userError "installed sibling artifact directory changed identity"))
              Just
                <$> either
                  (ioError . userError . ("derive sibling artifact generation lease: " <>))
                  pure
                  ( artifactGenerationLease
                      enginesRoot
                      siblingIdentity
                      (Artifact.manifestGenerationFingerprint manifest)
                      (Artifact.manifestDigest manifest)
                  )
      )
      entries

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
        (nativeArtifactTargetArchitecture target)
        lease
        -- Pre-publication: the candidate carries no manifest yet, so the helper
        -- gets the candidate validation shape rather than the installed one.
        Nothing
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
  AuthorizedWriterRoot ->
  LinuxCompletionState s 'LinuxGenerationExclusiveRevalidated ->
  IO (LinuxCompletionState s 'LinuxPublished)
publishLinuxCompletionState
  _generationAuthority
  authorizedRoot
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
    publishCandidateManifestFile authorizedRoot candidateRoot expectedManifest
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
  ArtifactInternal.ArtifactRootMutator w ->
  Subprocess.AbandonedActivitiesRecovered ->
  Subprocess.SubprocessEnv ->
  Internal.PositiveProvisioningTimeout ->
  LinuxCompletionState s 'LinuxPublished ->
  IO ()
activateLinuxCompletionState
  authority
  mutator
  recovered
  environment
  timeout
  ( LinuxPublishedCompletionState
      identity
      smokePolicy
      installRoot
      candidateRoot
      payloadDigest
      manifest
      lease
    ) = do
    expectedTargetEvidence <-
      maybe
        ( ioError
            ( userError
                "published Linux artifact manifest carries no exact image-target evidence"
            )
        )
        pure
        (Artifact.manifestImageTargetEvidence manifest)
    result <-
      ArtifactActivation.activateLinuxEngineArtifactWithInstalledSmoke
        authority
        mutator
        recovered
        lease
        environment
        timeout
        identity
        -- The published manifest is the authority for the activated
        -- generation's architecture, so the post-activation smoke resolves the
        -- same catalog entry the manifest's own target contract was minted
        -- from.
        (Artifact.manifestArchitecture manifest)
        (internalLinuxNativeSmokePolicy smokePolicy)
        expectedTargetEvidence
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
  writer
  grant
  deadline
  adapter
  installRoot
  candidateRoot
  manifestBuilder =
    void
      ( completeAppleCandidateWithSmoke
          writer
          grant
          deadline
          adapter
          installRoot
          candidateRoot
          manifestBuilder
          StandardAppleInstalledSmoke
      )

completeApplePythonCandidateWithSourceIsolation ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  CandidatePythonTarget s ->
  InstalledMachORuntimeClosure s ->
  FilePath ->
  FilePath ->
  AppleManifestBuilder ->
  ProvisioningSession s InstalledPythonSourceIsolationReport
completeApplePythonCandidateWithSourceIsolation
  writer
  grant
  deadline
  target
  runtimeClosure
  installRoot
  candidateRoot
  manifestBuilder = do
    let pythonAdapter = candidatePythonTargetInternalAdapter target
        adapter = Internal.appleAdapterForPython pythonAdapter
    _ <- requireCandidatePythonTarget pythonAdapter candidateRoot target
    unless
      ( normalise (installedMachORuntimeClosureRoot runtimeClosure)
          == normalise candidateRoot
      )
      (failProvisioningSession "installed Python runtime closure belongs to another candidate")
    sourceIsolationSpec <-
      ProvisioningSession
        (deriveInstalledPythonSourceIsolationSpec candidateRoot runtimeClosure)
    maybeReport <-
      completeAppleCandidateWithSmoke
        writer
        grant
        deadline
        (AppleAdapterId adapter)
        installRoot
        candidateRoot
        manifestBuilder
        (SourceIsolatedAppleInstalledSmoke pythonAdapter sourceIsolationSpec)
    maybe
      (failProvisioningSession "installed Python source-isolation completion produced no report")
      pure
      maybeReport

data AppleInstalledSmoke
  = StandardAppleInstalledSmoke
  | SourceIsolatedAppleInstalledSmoke
      !Internal.ApplePythonAdapterId
      !Internal.InstalledPythonSourceIsolationSpec

deriveInstalledPythonSourceIsolationSpec ::
  FilePath ->
  InstalledMachORuntimeClosure s ->
  IO Internal.InstalledPythonSourceIsolationSpec
deriveInstalledPythonSourceIsolationSpec candidateRoot runtimeClosure = do
  unless
    (SystemInfo.os == "darwin")
    (ioError (userError "installed Python source isolation requires Darwin"))
  unless
    ( normalise candidateRoot == candidateRoot
        && normalise (installedMachORuntimeClosureRoot runtimeClosure)
          == candidateRoot
        && not (null sources)
        && length sources <= 1024
    )
    (ioError (userError "installed Python source isolation has an invalid runtime closure"))
  classified <- mapM classifySource sources
  let directories =
        List.sortOn
          Internal.provisioningPackageClosureRoot
          [identity | SourceIsolationDirectory identity <- classified]
      classifiedFiles =
        List.sortOn
          Internal.provisioningRuntimeLibraryCanonicalPath
          [identity | SourceIsolationFile identity <- classified]
  frameworkHome <-
    case directories of
      [directory] -> pure directory
      _ ->
        ioError
          (userError "installed Python source isolation requires one framework home")
  writableProbe <-
    resolveWritableSourceIsolationProbe
      (Internal.provisioningPackageClosureRoot frameworkHome </> "Python")
  let files =
        List.sortOn
          Internal.provisioningRuntimeLibraryCanonicalPath
          ( writableProbe
              : filter
                ( ( /=
                      normalise
                        (Internal.provisioningRuntimeLibraryCanonicalPath writableProbe)
                  )
                    . normalise
                    . Internal.provisioningRuntimeLibraryCanonicalPath
                )
                classifiedFiles
          )
  unless
    ( length directories == 1
        && length files <= 512
        && length
          ( List.nub
              ( map Internal.provisioningPackageClosureRoot directories
                  <> map Internal.provisioningRuntimeLibraryCanonicalPath files
              )
          )
          == length directories + length files
    )
    (ioError (userError "installed Python source isolation has an invalid source cohort"))
  sandboxIdentity <-
    resolveExactExecutableIdentity
      Internal.installedPythonSourceIsolationSandboxExecutable
  unless
    ( normalise (resolvedExecutableConfiguredPath sandboxIdentity)
        == normalise Internal.installedPythonSourceIsolationSandboxExecutable
        && executableIdentityHasExecuteBit sandboxIdentity
    )
    (ioError (userError "fixed Darwin sandbox executable is unavailable"))
  auditInjectorIdentity <-
    resolveExactExecutableIdentity
      Internal.installedPythonSourceIsolationAuditInjectorExecutable
  unless
    ( normalise (resolvedExecutableConfiguredPath auditInjectorIdentity)
        == normalise Internal.installedPythonSourceIsolationAuditInjectorExecutable
        && executableIdentityHasExecuteBit auditInjectorIdentity
    )
    (ioError (userError "fixed Darwin loader-audit injector is unavailable"))
  let receipt =
        Internal.installedPythonSourceIsolationReceiptDigestFor
          directories
          files
  pure
    Internal.InstalledPythonSourceIsolationSpec
      { Internal.installedPythonSourceIsolationSandboxIdentity =
          toKernelExecutableIdentity sandboxIdentity [] [],
        Internal.installedPythonSourceIsolationAuditInjectorIdentity =
          toKernelExecutableIdentity auditInjectorIdentity [] [],
        Internal.installedPythonSourceIsolationDirectories = directories,
        Internal.installedPythonSourceIsolationFiles = files,
        Internal.installedPythonSourceIsolationWritableProbeIdentity =
          writableProbe,
        Internal.installedPythonSourceIsolationReceiptDigest = receipt
      }
  where
    sources = installedMachORuntimeClosureSources runtimeClosure

    classifySource source = do
      let sourcePath = installedRuntimeSourcePath source
          ownedPath = installedRuntimeOwnedPath source
      unless
        ( writerPathWithin candidateRoot ownedPath
            && normalise ownedPath == ownedPath
        )
        (ioError (userError "installed Python runtime evidence escaped its candidate root"))
      case List.stripPrefix "relative-link:" sourcePath of
        Just linkTarget -> do
          let relativeOwnedPath = makeRelative candidateRoot ownedPath
              encodedTarget = TextEncoding.encodeUtf8 (Text.pack linkTarget)
              expectedDigest =
                "sha256:"
                  <> TextEncoding.decodeUtf8
                    (Base16.encode (SHA256.hash encodedTarget))
          status <- Posix.getSymbolicLinkStatus ownedPath
          observedTarget <- Posix.readSymbolicLink ownedPath
          unless
            ( Posix.isSymbolicLink status
                && validRelativeClosureLink relativeOwnedPath linkTarget
                && observedTarget == linkTarget
                && installedRuntimeSourceFiles source == 1
                && installedRuntimeSourceBytes source
                  == fromIntegral (ByteString.length encodedTarget)
                && installedRuntimeSourceDigest source == expectedDigest
            )
            (ioError (userError "installed Python runtime link sentinel changed"))
          pure SourceIsolationOwnedLink
        Nothing -> do
          unless
            ( isAbsolute sourcePath
                && normalise sourcePath == sourcePath
                && not (writerPathWithin candidateRoot sourcePath)
                && not (writerPathWithin sourcePath candidateRoot)
            )
            (ioError (userError "installed Python source path is unsafe"))
          status <- Posix.getSymbolicLinkStatus sourcePath
          if
            | Posix.isDirectory status && not (Posix.isSymbolicLink status) -> do
                identity <-
                  resolvePackageClosureIdentity
                    Internal.ProvisioningPythonHomeClosure
                    sourcePath
                unless
                  ( Internal.provisioningPackageClosureFiles identity
                      == installedRuntimeSourceFiles source
                      && Internal.provisioningPackageClosureBytes identity
                        == installedRuntimeSourceBytes source
                      && Internal.provisioningPackageClosureDigest identity
                        == installedRuntimeSourceDigest source
                  )
                  (ioError (userError "installed Python source directory identity changed"))
                pure (SourceIsolationDirectory identity)
            | Posix.isRegularFile status && not (Posix.isSymbolicLink status) -> do
                resolved <- resolveExactExecutableIdentity sourcePath
                let identity =
                      runtimeLibraryIdentityFromResolved
                        (takeFileName sourcePath)
                        resolved
                unless
                  ( installedRuntimeSourceFiles source == 1
                      && Internal.provisioningRuntimeLibrarySize identity
                        == installedRuntimeSourceBytes source
                      && Internal.provisioningRuntimeLibraryDigest identity
                        == installedRuntimeSourceDigest source
                  )
                  (ioError (userError "installed Python source file identity changed"))
                pure (SourceIsolationFile identity)
            | otherwise ->
                ioError (userError "installed Python source is neither one exact directory nor file")

    resolveWritableSourceIsolationProbe path = do
      resolved <- resolveExactExecutableIdentity path
      let identity = runtimeLibraryIdentityFromResolved (takeFileName path) resolved
      descriptor <-
        openFd
          (Internal.provisioningRuntimeLibraryCanonicalPath identity)
          WriteOnly
          defaultFileFlags
            { nofollow = True,
              cloexec = True
            }
      finallyPreservingPrimary
        ( do
            status <- Posix.getFdStatus descriptor
            unless
              ( fromIntegral (Posix.deviceID status)
                  == Internal.provisioningRuntimeLibraryDeviceId identity
                  && fromIntegral (Posix.fileID status)
                    == Internal.provisioningRuntimeLibraryFileId identity
                  && fromIntegral (Posix.fileMode status)
                    == Internal.provisioningRuntimeLibraryMode identity
                  && fromIntegral (Posix.fileSize status)
                    == Internal.provisioningRuntimeLibrarySize identity
              )
              (ioError (userError "installed Python writable source probe identity changed"))
        )
        (closeFd descriptor)
      finalResolved <- resolveExactExecutableIdentity path
      unless
        (resolvedIdentityMatchesRuntimeIdentity finalResolved identity)
        (ioError (userError "installed Python writable source probe changed during preflight"))
      pure identity

data SourceIsolationClassifiedSource
  = SourceIsolationDirectory !Internal.ProvisioningPackageClosureIdentity
  | SourceIsolationFile !Internal.ProvisioningRuntimeLibraryIdentity
  | SourceIsolationOwnedLink

completeAppleCandidateWithSmoke ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  AppleAdapterId ->
  FilePath ->
  FilePath ->
  AppleManifestBuilder ->
  AppleInstalledSmoke ->
  ProvisioningSession s (Maybe InstalledPythonSourceIsolationReport)
completeAppleCandidateWithSmoke
  writer@(EngineWriter authority recovered authorizedRoot)
  (ProvisioningGrant environment)
  deadline@(ProvisioningDeadline timeout)
  (AppleAdapterId adapter)
  installRoot
  candidateRoot
  (AppleManifestBuilder buildManifest)
  installedSmoke =
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
                authorizedRoot
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
        (provisioningArtifactRootMutator writer)
        recovered
        environment
        timeout
        published
        manifest
        installedSmoke
      validateWriterRootIdentity
        "Apple candidate completion"
        authorizedRoot
      case installedSmoke of
        StandardAppleInstalledSmoke -> pure Nothing
        SourceIsolatedAppleInstalledSmoke pythonAdapter spec ->
          pure
            ( Just
                InstalledPythonSourceIsolationReport
                  { installedPythonSourceIsolationReportAdapter =
                      ApplePythonAdapterId pythonAdapter,
                    installedPythonSourceIsolationReportInstallRoot =
                      authorizedInstallRoot,
                    installedPythonSourceIsolationReportArtifactDigest =
                      Artifact.manifestDigest manifest,
                    installedPythonSourceIsolationReportReceiptDigest =
                      Internal.installedPythonSourceIsolationReceiptDigest spec,
                    installedPythonSourceIsolationReportDirectoryCount =
                      length (Internal.installedPythonSourceIsolationDirectories spec),
                    installedPythonSourceIsolationReportFileCount =
                      length (Internal.installedPythonSourceIsolationFiles spec)
                  }
            )

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
  AuthorizedWriterRoot ->
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
  authorizedRoot
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
    publishCandidateManifestFile authorizedRoot candidateRoot manifest
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
  ArtifactInternal.ArtifactRootMutator w ->
  Subprocess.AbandonedActivitiesRecovered ->
  Subprocess.SubprocessEnv ->
  Internal.PositiveProvisioningTimeout ->
  AppleCompletionState s 'Published ->
  Artifact.EngineArtifactManifest ->
  AppleInstalledSmoke ->
  IO ()
activateAppleCompletionState
  authority
  mutator
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
  _manifest
  installedSmoke = do
    result <-
      case installedSmoke of
        StandardAppleInstalledSmoke ->
          ArtifactActivation.activateAppleEngineArtifactWithInstalledSmoke
            authority
            mutator
            recovered
            lease
            environment
            timeout
            adapter
            installRoot
            candidateRoot
            digest
        SourceIsolatedAppleInstalledSmoke pythonAdapter sourceIsolationSpec -> do
          unless
            (Internal.appleAdapterForPython pythonAdapter == adapter)
            (ioError (userError "source-isolation smoke adapter changed before activation"))
          ArtifactActivation.activateAppleEngineArtifactWithInstalledPythonSourceIsolationSmoke
            authority
            mutator
            recovered
            lease
            environment
            timeout
            adapter
            sourceIsolationSpec
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

-- | Publish a candidate's manifest through the retained parent descriptor of its
-- authorized writer root.
--
-- The superseded form took no writer root at all: it created the manifest with a
-- full-path @openFd@, unlinked it by pathname on failure, and fsynced
-- @candidateRoot@ by pathname. A candidate root swapped between any two of those
-- steps redirected the manifest write, the rollback, or the durability proof.
-- The manifest is one leaf directly under the candidate root, so
-- 'writeAuthorizedRegularFile' -- which retains the parent, opens the leaf
-- @O_NOFOLLOW@ on it, and fsyncs both -- is the exact shape needed.
publishCandidateManifestFile ::
  AuthorizedWriterRoot ->
  FilePath ->
  Artifact.EngineArtifactManifest ->
  IO ()
publishCandidateManifestFile authorizedRoot candidateRoot manifest = do
  let manifestPath = Artifact.engineArtifactManifestPath candidateRoot
      contents =
        LazyByteString.toStrict
          (Artifact.renderEngineArtifactManifest manifest)
  unless
    (ByteString.length contents <= maximumCandidateManifestBytes)
    (ioError (userError "candidate manifest exceeds its fixed byte bound"))
  onExceptionPreservingPrimary
    ( writeAuthorizedRegularFile
        "candidate manifest publication"
        authorizedRoot
        manifestPath
        contents
    )
    ( removeAuthorizedLeafThroughKernel
        "candidate manifest rollback"
        authorizedRoot
        manifestPath
    )
  validateWriterRootIdentity "candidate manifest publication" authorizedRoot

-- | The fixed bound on a published candidate manifest.
maximumCandidateManifestBytes :: Int
maximumCandidateManifestBytes = 1024 * 1024

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
            hostBinaryPayloadOkay "llama-completion"
          Internal.WhisperCppCliAdapter ->
            hostBinaryPayloadOkay "whisper-cli"
          Internal.CTranslate2Adapter -> pythonPayloadOkay
          Internal.OnnxRuntimeAdapter -> pythonPayloadOkay
          Internal.MlxAdapter -> pythonPayloadOkay
          Internal.CoreMlAdapter -> pythonPayloadOkay
          Internal.JvmAdapter -> do
            appLauncherOkay <-
              regularExecutable
                ( candidateRoot
                    </> "Audiveris.app"
                    </> "Contents"
                    </> "MacOS"
                    </> "Audiveris"
                )
            javaCppCacheOkay <- regularDirectory (candidateRoot </> "javacpp-cache")
            pure (appLauncherOkay && javaCppCacheOkay)
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
      pure (maybe False realDirectoryStatus statusResult)
    regularExecutable path = do
      statusResult <- tryPathStatus path
      case statusResult of
        Just status
          | Posix.isRegularFile status
              && not (Posix.isSymbolicLink status) ->
              -- The mode is already in the status just observed, so asking
              -- @Directory.getPermissions@ only re-resolved the same pathname a
              -- second time and could answer about a different file.
              pure (executableFileMode status)
        _ -> pure False
    regularFile path = do
      statusResult <- tryPathStatus path
      pure (maybe False realRegularFileStatus statusResult)
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

-- | Observe an executable below the locked Poetry project without granting
-- the caller raw filesystem authority. A stable absence is @Right False@;
-- dangling links, permission failures, identity changes, and every other
-- malformed observation are @Left@ so a producer cannot mistake an
-- unavailable observation for permission to publish readiness.
--
-- Poetry normally creates @.venv/bin/python@ as a symlink. Resolve and digest
-- its exact target, then revalidate that identity while the project mutation
-- lock is held rather than rejecting the normal venv layout merely because
-- its configured entry is a link.
provisioningProjectExecutableReady ::
  ProjectWriter p s q ->
  FilePath ->
  ProvisioningSession s (Either String Bool)
provisioningProjectExecutableReady
  (ProjectWriter _ projectRoot)
  requestedPath =
    ProvisioningSession $ do
      observed <-
        try @IOException $ do
          _ <-
            authorizedWriterRelativeComponents
              "project executable observation"
              projectRoot
              requestedPath
          validateWriterRootIdentity
            "project executable observation"
            projectRoot
          present <- Directory.doesPathExist requestedPath
          if not present
            then pure False
            else do
              identity <- resolveExactExecutableIdentity requestedPath
              revalidated <- revalidateExecutableIdentity identity
              either (ioError . userError) pure revalidated
              validateWriterRootIdentity
                "project executable observation"
                projectRoot
              pure (executableIdentityHasExecuteBit identity)
      pure (displayCaughtProvisioningFailure observed)

-- | Bounded, descriptor-retained read below the locked Poetry project. The
-- @Maybe@ distinguishes a stable absence from a present file; the outer
-- @Either@ keeps malformed, oversized, symlinked, or changing entries
-- fail-closed. This is the observation half of the prepared-framework marker
-- protocol; publication continues through 'provisioningProjectWriteFile'.
provisioningProjectReadFile ::
  ProjectWriter p s q ->
  FilePath ->
  Integer ->
  ProvisioningSession s (Either String (Maybe ByteString.ByteString))
provisioningProjectReadFile
  (ProjectWriter _ projectRoot)
  requestedPath
  maximumBytes =
    ProvisioningSession $ do
      observed <-
        try @IOException $ do
          validateWriterRootIdentity
            "project bounded file read"
            projectRoot
          status <-
            observeAuthorizedPathStatus
              "project bounded file read"
              projectRoot
              requestedPath
          contents <-
            case status of
              Nothing -> pure Nothing
              Just fileStatus -> do
                unless
                  (realRegularFileStatus fileStatus)
                  (ioError (userError "project bounded file read is not a real regular file"))
                Just
                  <$> readAuthorizedRegularFile
                    "project bounded file read"
                    projectRoot
                    requestedPath
                    maximumBytes
          validateWriterRootIdentity
            "project bounded file read"
            projectRoot
          pure contents
      pure (displayCaughtProvisioningFailure observed)

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
        ( if maybe False executableRegularFileStatus observed
            then Just executable
            else Nothing
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
      pure (either (const False) (== expected) observed)

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
                            -- The write legitimately changes size and mtime,
                            -- so the pre/post comparison is object identity and
                            -- mode; the sealed comparison against the reopened
                            -- entry stays exact.
                            unless
                              ( sameFileObject status finalStatus
                                  && Posix.fileMode status
                                    == Posix.fileMode finalStatus
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
            -- The authorized action mutates this directory, so its size and
            -- timestamps legitimately change. The invariant is that the
            -- retained descriptor still names the same directory object with
            -- the same mode, not that the directory was left untouched.
            unless
              ( Posix.isDirectory parentStatus
                  && Posix.isDirectory finalParentStatus
                  && sameFileObject parentStatus finalParentStatus
                  && Posix.fileMode parentStatus
                    == Posix.fileMode finalParentStatus
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

-- | Create or replace one owned leaf through its retained parent descriptor.
--
-- @authorizedWriterPath@ validates a path's ancestry and then returns a
-- @FilePath@, closing every descriptor it opened. Any effect performed on that
-- result re-resolves the whole path through the namespace, so an adversary can
-- swap an intermediate parent between the check and the effect. This helper
-- closes that window: the leaf is opened with @openFdAt@ relative to the parent
-- descriptor @withAuthorizedLeafParent@ retains, the bytes go to that
-- descriptor, and both the file and the retained parent are fsynced. Nothing
-- between the ancestry check and the effect names a path.
--
-- @nofollow@ makes a symlink planted at the leaf a failure rather than a
-- redirect, and @trunc@ gives create-or-replace semantics without a separate
-- unlink step that would reopen the same window.
writeAuthorizedRegularFile ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  ByteString.ByteString ->
  IO ()
writeAuthorizedRegularFile =
  writeAuthorizedRegularFileWithParentSwapPause Nothing

-- | The retained-parent write with an explicitly named adversarial checkpoint.
--
-- The optional cells are signalled after 'withAuthorizedLeafParent' has walked
-- and retained the destination parent and before the leaf is opened on that
-- descriptor. That is exactly the window in which a pathname-resolving writer
-- would be redirected by an intermediate-parent swap, so it is the only window
-- in which a deterministic test can prove the retained descriptor is what the
-- effect actually follows.
--
-- The seam can only signal and await already-created synchronization cells. It
-- grants the caller no raw IO, filesystem, process, or writer authority, which
-- is the same bound 'pauseProvisioningSessionForTest' observes.
writeAuthorizedRegularFileWithParentSwapPause ::
  Maybe (MVar (), MVar ()) ->
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  ByteString.ByteString ->
  IO ()
writeAuthorizedRegularFileWithParentSwapPause
  pauseBeforeLeaf
  label
  authorizedRoot
  requestedPath
  contents =
    withAuthorizedLeafParent
      label
      authorizedRoot
      requestedPath
      (writeAuthorizedLeafAfterPause label pauseBeforeLeaf contents)

writeAuthorizedLeafAfterPause ::
  String ->
  Maybe (MVar (), MVar ()) ->
  ByteString.ByteString ->
  Fd ->
  FilePath ->
  IO ()
writeAuthorizedLeafAfterPause
  label
  pauseBeforeLeaf
  contents
  parentDescriptor
  leaf = do
    mapM_ awaitParentSwapCheckpoint pauseBeforeLeaf
    writeAuthorizedLeafContents label contents parentDescriptor leaf

awaitParentSwapCheckpoint :: (MVar (), MVar ()) -> IO ()
awaitParentSwapCheckpoint (entered, resume) = do
  putMVar entered ()
  takeMVar resume

writeAuthorizedLeafContents ::
  String ->
  ByteString.ByteString ->
  Fd ->
  FilePath ->
  IO ()
writeAuthorizedLeafContents label contents parentDescriptor leaf =
  mask $ \restore -> do
    descriptor <-
      openFdAt
        (Just parentDescriptor)
        leaf
        WriteOnly
        defaultFileFlags
          { nofollow = True,
            trunc = True,
            creat =
              Just
                ( Posix.ownerReadMode
                    .|. Posix.ownerWriteMode
                ),
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          status <- Posix.getFdStatus descriptor
          unless
            (Posix.isRegularFile status)
            (ioError (userError (label <> " destination is not a regular file")))
          writeProvisioningDescriptor descriptor contents
          fileSynchronise descriptor
          fileSynchronise parentDescriptor
      )
      (closeFd descriptor)

-- | Add the owner-execute bit to one owned leaf through its retained parent
-- descriptor.
--
-- The mode is set on the descriptor rather than on a pathname, so the file
-- whose ancestry was validated is the file whose mode changes. The previous
-- @Directory.getPermissions@ / @Directory.setPermissions@ pair re-resolved the
-- path twice after the probe.
setAuthorizedLeafExecutable ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
setAuthorizedLeafExecutable label authorizedRoot requestedPath =
  withAuthorizedLeafParent
    label
    authorizedRoot
    requestedPath
    (setAuthorizedLeafExecutableMode label)

setAuthorizedLeafExecutableMode ::
  String ->
  Fd ->
  FilePath ->
  IO ()
setAuthorizedLeafExecutableMode label parentDescriptor leaf =
  mask $ \restore -> do
    descriptor <-
      openFdAt
        (Just parentDescriptor)
        leaf
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True
          }
    finallyPreservingPrimary
      ( restore $ do
          status <- Posix.getFdStatus descriptor
          unless
            (Posix.isRegularFile status)
            (ioError (userError (label <> " target is not a regular file")))
          Posix.setFdMode
            descriptor
            (Posix.fileMode status .|. Posix.ownerExecuteMode)
          fileSynchronise parentDescriptor
      )
      (closeFd descriptor)

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

-- | The one interpreter for the artifact transaction's closed parent-level
-- mutation language.
--
-- The transaction lives in @Engines.Artifact.Internal@, which cannot import the
-- mutation kernel without closing an import cycle through
-- @Cluster.Subprocess@. It therefore requests the two effects it needs and this
-- function -- the only place that holds both the writer root and the kernel --
-- performs them through a retained parent descriptor.
--
-- Every operand is revalidated here, beside the effect rather than at some
-- earlier boundary: both operands must resolve inside this writer root, a
-- rename's two paths must share a parent so it is genuinely a sibling rename,
-- and the components handed to the kernel are re-derived from the authorized
-- path rather than carried from the caller.
-- | Interpret exactly one root mutation through the production interpreter
-- under a real engine writer.
--
-- @infernix-artifact-transaction@ exercises the pathname test interpreter by
-- design, so it proves the transaction's ordering and nothing about
-- 'provisioningArtifactRootMutator'. This is the only seam that reaches the
-- production interpreter and the descriptor-anchored kernel it drives. The
-- interpreter value itself never escapes: the effect is confined to the
-- session, and the authority still comes only from an 'EngineWriter' obtained
-- inside 'withEngineProvisioningSession'.
provisioningInterpretArtifactRootMutationForTest ::
  EngineWriter w s q ->
  ArtifactInternal.ArtifactRootMutation ->
  ProvisioningSession s ()
provisioningInterpretArtifactRootMutationForTest writer mutation =
  ProvisioningSession
    ( ArtifactInternal.runArtifactRootMutation
        (provisioningArtifactRootMutator writer)
        mutation
    )

provisioningArtifactRootMutator ::
  EngineWriter w s q ->
  ArtifactInternal.ArtifactRootMutator w
provisioningArtifactRootMutator (EngineWriter _ _ authorizedRoot) =
  ArtifactInternal.ArtifactRootMutator interpret
  where
    interpret mutation =
      case mutation of
        ArtifactInternal.RemoveArtifactRootSibling path ->
          removeAuthorizedLeafThroughKernel
            "artifact root retirement"
            authorizedRoot
            path
        ArtifactInternal.RenameArtifactRootSibling source destination -> do
          sourceComponents <-
            authorizedWriterRelativeComponents
              "artifact root rename source"
              authorizedRoot
              source
          destinationComponents <-
            authorizedWriterRelativeComponents
              "artifact root rename destination"
              authorizedRoot
              destination
          unless
            (init sourceComponents == init destinationComponents)
            ( ioError
                ( userError
                    "artifact root rename operands are not siblings"
                )
            )
          runAuthorizedFilesystemMutation
            "artifact root rename"
            authorizedRoot
            ( Subprocess.provisioningRenameSiblingDirectory
                (authorizedWriterMutationRoot authorizedRoot)
                (init sourceComponents)
                (last sourceComponents)
                (last destinationComponents)
            )

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
              (StableCopySourceInRoot authorizedRoot)
              authorizedRoot
              maximumBytes
              authorizedSource
              authorizedDestination
          validateWriterRootIdentity "stable copy" authorizedRoot
          pure copied

maximumStableCopyBytes :: Integer
maximumStableCopyBytes = 2 * 1024 * 1024 * 1024

-- | The bound on the repo-owned Apple native runner library. It is one Python
-- module, measured well under this.
appleNativeRunnerLibraryBytes :: Int
appleNativeRunnerLibraryBytes = 1024 * 1024

-- | Where a stable copy reads its bytes from.
--
-- A source inside an authorized writer root is read through that root's
-- retained parent descriptor, so an intermediate parent swapped at the read
-- boundary is a failure rather than a redirect.
--
-- An arbitrary source outside every owned root has no retained traversal -- a
-- host CLI or runtime library resolved only by pathname lives under a Homebrew
-- or system prefix. Such a source is bound by the exact content digest its
-- caller already resolved. For a /read/ that is the stronger binding: it
-- constrains the bytes actually copied rather than the directory they were
-- reached through, so a source swapped mid-copy fails on content even when the
-- pathname still resolves.
--
-- A package-closure entry is different: the bounded recursive walk already
-- owns its nofollow source-parent and file descriptors. That retained custody
-- is carried directly into the copy; it must not be misclassified as a source
-- inside the unrelated destination writer root.
data StableCopySource
  = StableCopySourceInRoot !AuthorizedWriterRoot
  | StableCopySourceExactContent !Text
  | StableCopySourceRetainedDescriptor
      !Fd
      !Posix.FileStatus
      !(IO ())

-- | Copy one regular file into an authorized writer root, descriptor-anchored
-- on both sides.
--
-- The destination is created, written, mode-set, verified, and -- on failure --
-- removed entirely through the parent descriptor 'withAuthorizedLeafParent'
-- retains, and that same descriptor is the one fsynced. The superseded form
-- opened both sides by full pathname and fsynced @takeDirectory destination@,
-- so every one of those effects re-resolved the path and an intermediate parent
-- swapped between them redirected the write.
copyRegularFileStable ::
  StableCopySource ->
  AuthorizedWriterRoot ->
  Integer ->
  FilePath ->
  FilePath ->
  IO (StableFileCopyEvidence s)
copyRegularFileStable
  sourceAuthority
  destinationRoot
  maximumBytes
  source
  destination =
    withStableCopySourceDescriptor
      sourceAuthority
      maximumBytes
      source
      ( \sourceDescriptor listedStatus recheckSource ->
          withAuthorizedLeafParent
            "stable copy destination"
            destinationRoot
            destination
            ( \destinationParent destinationLeaf ->
                copyIntoRetainedDestination
                  destinationRoot
                  destinationParent
                  destinationLeaf
                  destination
                  maximumBytes
                  sourceDescriptor
                  listedStatus
                  recheckSource
                  (stableCopyExpectedDigest sourceAuthority)
            )
      )

-- | Copy one regular file into a destination parent the caller already retains.
--
-- The recursive package-closure walk holds a descriptor on each destination
-- directory as it descends, so re-deriving that parent from the writer root for
-- every one of tens of thousands of entries would both re-resolve the pathname
-- and re-walk the whole ancestry. This form consumes the descriptor the walk
-- already holds.
copyRegularFileStableIntoRetainedParent ::
  StableCopySource ->
  AuthorizedWriterRoot ->
  Fd ->
  FilePath ->
  Integer ->
  FilePath ->
  FilePath ->
  IO (StableFileCopyEvidence s)
copyRegularFileStableIntoRetainedParent
  sourceAuthority
  destinationRoot
  destinationParent
  destinationLeaf
  maximumBytes
  source
  destination =
    withStableCopySourceDescriptor
      sourceAuthority
      maximumBytes
      source
      ( \sourceDescriptor listedStatus recheckSource ->
          copyIntoRetainedDestination
            destinationRoot
            destinationParent
            destinationLeaf
            destination
            maximumBytes
            sourceDescriptor
            listedStatus
            recheckSource
            (stableCopyExpectedDigest sourceAuthority)
      )

-- | The content digest a source authority binds its bytes to, if any.
stableCopyExpectedDigest :: StableCopySource -> Maybe Text
stableCopyExpectedDigest sourceAuthority =
  case sourceAuthority of
    StableCopySourceInRoot _ -> Nothing
    StableCopySourceExactContent expected -> Just expected
    StableCopySourceRetainedDescriptor {} -> Nothing

-- | Open a stable copy's source and hand its descriptor, its initial status, and
-- an unchanged-since-open recheck to the copy.
withStableCopySourceDescriptor ::
  StableCopySource ->
  Integer ->
  FilePath ->
  (Fd -> Posix.FileStatus -> IO () -> IO result) ->
  IO result
withStableCopySourceDescriptor sourceAuthority maximumBytes source action =
  case sourceAuthority of
    StableCopySourceInRoot sourceRoot ->
      withAuthorizedLeafParent
        "stable copy source"
        sourceRoot
        source
        ( \sourceParent sourceLeaf -> do
            descriptor <-
              openFdAt
                (Just sourceParent)
                sourceLeaf
                ReadOnly
                defaultFileFlags
                  { nofollow = True,
                    cloexec = True
                  }
            finallyPreservingPrimary
              ( do
                  openedStatus <- Posix.getFdStatus descriptor
                  requireStableCopySource source maximumBytes openedStatus
                  action
                    descriptor
                    openedStatus
                    ( do
                        finalStatus <- Posix.getFdStatus descriptor
                        reopenedStatus <-
                          reopenFileEntryStatus sourceParent sourceLeaf
                        unless
                          ( stableExecutableStatus openedStatus finalStatus
                              && stableExecutableStatus finalStatus reopenedStatus
                          )
                          (ioError (userError ("stable copy source changed while copying: " <> source)))
                    )
              )
              (closeFd descriptor)
        )
    StableCopySourceExactContent _ -> mask $ \restore -> do
      listedStatus <- Posix.getSymbolicLinkStatus source
      requireStableCopySource source maximumBytes listedStatus
      descriptor <-
        openFd
          source
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
              (ioError (userError ("stable copy source changed before open: " <> source)))
            action
              descriptor
              openedStatus
              ( do
                  finalStatus <- Posix.getFdStatus descriptor
                  finalPathStatus <- Posix.getSymbolicLinkStatus source
                  unless
                    ( stableExecutableStatus openedStatus finalStatus
                        && stableExecutableStatus finalStatus finalPathStatus
                    )
                    (ioError (userError ("stable copy source changed while copying: " <> source)))
              )
        )
        (closeFd descriptor)
    -- The package-closure traversal already reached this file through a
    -- retained, nofollow directory chain and owns the descriptor until its
    -- enclosing bracket returns. Reusing that descriptor preserves the source
    -- custody without pretending the external Homebrew/Python closure lies
    -- under the destination engine writer root.
    StableCopySourceRetainedDescriptor descriptor listedStatus recheckSource -> do
      openedStatus <- Posix.getFdStatus descriptor
      unless
        (stableExecutableStatus listedStatus openedStatus)
        (ioError (userError ("stable copy source changed before copy: " <> source)))
      requireStableCopySource source maximumBytes openedStatus
      _ <- fdSeek descriptor AbsoluteSeek 0
      action descriptor listedStatus recheckSource

-- | A stable copy source must be a bounded real regular file.
requireStableCopySource ::
  FilePath ->
  Integer ->
  Posix.FileStatus ->
  IO ()
requireStableCopySource source maximumBytes status =
  unless
    ( Posix.isRegularFile status
        && not (Posix.isSymbolicLink status)
        && fromIntegral (Posix.fileSize status) <= maximumBytes
    )
    (ioError (userError ("stable copy source is invalid: " <> source)))

-- | Create, write, verify, and make durable one copy destination under a
-- retained parent descriptor.
copyIntoRetainedDestination ::
  AuthorizedWriterRoot ->
  Fd ->
  FilePath ->
  FilePath ->
  Integer ->
  Fd ->
  Posix.FileStatus ->
  IO () ->
  Maybe Text ->
  IO (StableFileCopyEvidence s)
copyIntoRetainedDestination
  destinationRoot
  destinationParent
  destinationLeaf
  destination
  maximumBytes
  sourceDescriptor
  listedStatus
  recheckSource
  expectedDigest = mask $ \restore -> do
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
    destinationOpenedStatus <-
      onExceptionPreservingPrimary
        (Posix.getFdStatus destinationDescriptor)
        (closeFd destinationDescriptor)
    let cleanupDestination = do
          _ <- try @IOException (closeFd destinationDescriptor)
          removeStableDestinationIfOwned
            destinationRoot
            destinationParent
            destinationLeaf
            destination
            destinationOpenedStatus
    onExceptionPreservingPrimary
      ( finallyPreservingPrimary
          ( restore
              ( finishStableCopy
                  destinationParent
                  destinationLeaf
                  destination
                  maximumBytes
                  sourceDescriptor
                  listedStatus
                  recheckSource
                  expectedDigest
                  destinationDescriptor
                  destinationOpenedStatus
              )
          )
          (closeFd destinationDescriptor)
      )
      cleanupDestination

-- | Copy the bytes, verify both sides, and fsync the retained parent.
finishStableCopy ::
  Fd ->
  FilePath ->
  FilePath ->
  Integer ->
  Fd ->
  Posix.FileStatus ->
  IO () ->
  Maybe Text ->
  Fd ->
  Posix.FileStatus ->
  IO (StableFileCopyEvidence s)
finishStableCopy
  destinationParent
  destinationLeaf
  destination
  maximumBytes
  sourceDescriptor
  listedStatus
  recheckSource
  expectedDigest
  destinationDescriptor
  destinationOpenedStatus = do
    unless
      (Posix.isRegularFile destinationOpenedStatus)
      (ioError (userError ("stable copy destination is not regular: " <> destination)))
    (copiedBytes, sourceContext) <-
      copyProvisioningDescriptor
        sourceDescriptor
        destinationDescriptor
        0
        SHA256.init
        maximumBytes
    recheckSource
    let sourceDigest =
          "sha256:"
            <> TextEncoding.decodeUtf8
              (Base16.encode (SHA256.finalize sourceContext))
        destinationMode = stableCopyDestinationMode listedStatus
    unless
      ( copiedBytes == fromIntegral (Posix.fileSize listedStatus)
          && maybe True (== sourceDigest) expectedDigest
      )
      (ioError (userError ("stable copy did not reproduce its exact source: " <> destination)))
    Posix.setFdMode destinationDescriptor destinationMode
    fileSynchronise destinationDescriptor
    _ <- fdSeek destinationDescriptor AbsoluteSeek 0
    destinationContext <-
      hashExecutableDescriptor SHA256.init destinationDescriptor
    stableDestinationStatus <- Posix.getFdStatus destinationDescriptor
    destinationStatus <-
      reopenFileEntryStatus destinationParent destinationLeaf
    finalDestinationStatus <- Posix.getFdStatus destinationDescriptor
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
    synchroniseProvisioningDescriptor destinationParent
    pure
      StableFileCopyEvidence
        { stableFileCopyDigest = destinationDigest,
          stableFileCopyInfo =
            pathInfoFromStatus stableDestinationStatus
        }

-- | The mode a stable copy's destination carries: owner-readable, and
-- owner-executable exactly when the source was executable by anyone.
stableCopyDestinationMode :: Posix.FileStatus -> FileMode
stableCopyDestinationMode listedStatus =
  Posix.ownerReadMode
    .|. ( if sourceExecutable
            then Posix.ownerExecuteMode
            else 0
        )
  where
    sourceExecutable =
      Posix.fileMode listedStatus
        .&. ( Posix.ownerExecuteMode
                .|. Posix.groupExecuteMode
                .|. Posix.otherExecuteMode
            )
        /= 0

sameFileObject :: Posix.FileStatus -> Posix.FileStatus -> Bool
sameFileObject expected observed =
  Posix.deviceID expected == Posix.deviceID observed
    && Posix.fileID expected == Posix.fileID observed

-- | Remove a failed copy's destination, but only while the entry under the
-- retained parent is still the exact file object this copy created.
--
-- The entry is re-observed through the retained parent descriptor rather than by
-- re-resolving the pathname, so a parent swapped after the failure cannot
-- redirect the removal onto an unrelated file. The removal itself goes through
-- the mutation kernel, which is the only descriptor-anchored unlink available.
removeStableDestinationIfOwned ::
  AuthorizedWriterRoot ->
  Fd ->
  FilePath ->
  FilePath ->
  Posix.FileStatus ->
  IO ()
removeStableDestinationIfOwned
  destinationRoot
  destinationParent
  destinationLeaf
  destination
  expected = do
    observed <-
      try @IOException (reopenFileEntryStatus destinationParent destinationLeaf)
    case observed of
      Right status
        | sameFileObject expected status -> do
            removeAuthorizedLeafThroughKernel
              "stable copy rollback"
              destinationRoot
              destination
            synchroniseProvisioningDescriptor destinationParent
      _ -> pure ()

copyProvisioningDescriptor ::
  Fd ->
  Fd ->
  Integer ->
  SHA256.Ctx ->
  Integer ->
  IO (Integer, SHA256.Ctx)
copyProvisioningDescriptor source destination copiedBytes context maximumBytes = do
  chunk <- readProvisioningDescriptorChunk source (64 * 1024)
  if ByteString.null chunk
    then pure (copiedBytes, context)
    else do
      let nextBytes =
            copiedBytes + fromIntegral (ByteString.length chunk)
      unless
        (nextBytes <= maximumBytes)
        (ioError (userError "stable copy exceeded its fixed byte bound"))
      writeProvisioningDescriptor destination chunk
      let nextContext = SHA256.update context chunk
      nextContext `seq`
        copyProvisioningDescriptor
          source
          destination
          nextBytes
          nextContext
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
          -- The runner library is repo-owned and lies outside every writer root,
          -- so it has no retained parent. Digesting it first and requiring the
          -- copy to reproduce that digest binds the copied bytes: a source
          -- swapped between the two reads fails closed rather than being
          -- installed.
          sourceBytes <-
            readRegularFileNoFollowBounded
              sourcePath
              appleNativeRunnerLibraryBytes
          _ <-
            copyRegularFileStable
              ( StableCopySourceExactContent
                  ( "sha256:"
                      <> TextEncoding.decodeUtf8
                        (Base16.encode (SHA256.hash sourceBytes))
                  )
              )
              authorizedRoot
              (fromIntegral appleNativeRunnerLibraryBytes)
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
          let EngineWriter _ _ authorizedRoot = writer
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
                authorizedRoot
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

-- | Rewrite a candidate venv's launchers and configuration to their final root.
--
-- Everything below the candidate root was already descriptor-anchored; the root
-- itself was reached by a single full-path @openFd@, which made it the one
-- swappable point in the whole traversal. It is now reached through the writer
-- root's retained ancestry.
relocateCandidateVenvExact ::
  AuthorizedWriterRoot ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  ByteString.ByteString ->
  IO ()
relocateCandidateVenvExact
  authorizedRoot
  installRoot
  candidateRoot
  oldRootBytes
  newRootBytes =
    withRetainedAuthorizedDirectory
      "candidate relocation root"
      authorizedRoot
      candidateRoot
      ( \rootDescriptor -> do
          openedRootStatus <- Posix.getFdStatus rootDescriptor
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
                    venvDescriptor
                requireNoRelocationResidual
                  candidateRoot
                  rootDescriptor
                  openedRootStatus
                  (oldRootBytes : sourcePythonPaths)
            )
      )

rewritePyvenvConfigExact ::
  FilePath ->
  FilePath ->
  Fd ->
  IO [ByteString.ByteString]
rewritePyvenvConfigExact
  installRoot
  candidateRoot
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
            -- The reopen goes through the retained venv descriptor, which is
            -- what makes it evidence. The superseded chain also stat'ed
            -- @venvPath \<\/\> "pyvenv.cfg"@ by pathname, which re-resolved the
            -- whole ancestry the retained descriptor exists to pin.
            reopenedStatus <-
              reopenFileEntryStatus venvDescriptor "pyvenv.cfg"
            unless
              ( observed == rewrittenBytes
                  && sameFileObject openedStatus finalStatus
                  && stableExecutableStatus finalStatus reopenedStatus
              )
              (ioError (userError "rewritten pyvenv.cfg did not seal"))
            synchroniseProvisioningDescriptor venvDescriptor
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
      synchroniseProvisioningDescriptor parentDescriptor

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
    Left openFailure -> do
      -- A candidate entry the rewrite pass could not open for writing is not
      -- necessarily a directory or a symlink. A copied interpreter such as
      -- `venv/bin/infernix-python` is a read-and-execute regular file, so the
      -- rewrite open fails with EACCES and the directory probe then fails with
      -- ENOTDIR. Skipping it here is safe because nothing is assumed about its
      -- contents: the residual scan reads every regular file in the activated
      -- candidate and fails closed if any still carries the pre-relocation
      -- root, so a file that genuinely needed rewriting cannot pass unnoticed.
      entryStatus <- Posix.getSymbolicLinkStatus path
      if Posix.isRegularFile entryStatus
        then pure ()
        else do
          _ <-
            validateStableProvisioningSymlink
              parentPath
              parentDescriptor
              path
              openFailure
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
      Left openFailure -> do
        target <-
          validateStableProvisioningSymlink
            parentPath
            parentDescriptor
            path
            openFailure
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
      prefix <- readProvisioningDescriptorChunk descriptor 2
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
  IOException ->
  IO ByteString.ByteString
validateStableProvisioningSymlink parentPath parentDescriptor path openFailure = do
  parentStatus <- Posix.getFdStatus parentDescriptor
  parentPathStatus <- Posix.getSymbolicLinkStatus parentPath
  status <- Posix.getSymbolicLinkStatus path
  -- Carry the open failure: without it a caller cannot tell a permission
  -- problem from an unsupported entry kind, and the candidate that produced it
  -- is retired before it can be inspected.
  unless
    (Posix.isSymbolicLink status)
    ( ioError
        ( userError
            ( "provisioning entry is neither openable nor a symlink: "
                <> path
                <> "; open failed with "
                <> displayException openFailure
            )
        )
    )
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
          chunk <- readProvisioningDescriptorChunk descriptor requested
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
    writeAuthorizedRegularFile
      "engine text write"
      authorizedRoot
      path
      (TextEncoding.encodeUtf8 (Text.pack contents))
    validateWriterRootIdentity "engine text write" authorizedRoot

provisioningProjectWriteFile ::
  ProjectWriter p s q ->
  FilePath ->
  String ->
  ProvisioningSession s ()
provisioningProjectWriteFile (ProjectWriter _ authorizedRoot) path contents =
  ProvisioningSession $ do
    writeAuthorizedRegularFile
      "project text write"
      authorizedRoot
      path
      (TextEncoding.encodeUtf8 (Text.pack contents))
    validateWriterRootIdentity "project text write" authorizedRoot

provisioningWriteBytes ::
  EngineWriter w s q ->
  FilePath ->
  ByteString.ByteString ->
  ProvisioningSession s ()
provisioningWriteBytes =
  provisioningWriteBytesWithPause Nothing

-- | The engine byte write with the adversarial parent-swap checkpoint of
-- 'writeAuthorizedRegularFileWithParentSwapPause' exposed to a deterministic
-- test. Named for what it is: the seam a swap fixture plants its substitute
-- through.
provisioningWriteBytesWithParentSwapPauseForTest ::
  EngineWriter w s q ->
  FilePath ->
  ByteString.ByteString ->
  MVar () ->
  MVar () ->
  ProvisioningSession s ()
provisioningWriteBytesWithParentSwapPauseForTest
  writer
  path
  contents
  entered
  resume =
    provisioningWriteBytesWithPause
      (Just (entered, resume))
      writer
      path
      contents

provisioningWriteBytesWithPause ::
  Maybe (MVar (), MVar ()) ->
  EngineWriter w s q ->
  FilePath ->
  ByteString.ByteString ->
  ProvisioningSession s ()
provisioningWriteBytesWithPause
  pauseBeforeLeaf
  (EngineWriter _ _ authorizedRoot)
  path
  contents =
    ProvisioningSession $ do
      writeAuthorizedRegularFileWithParentSwapPause
        pauseBeforeLeaf
        "engine byte write"
        authorizedRoot
        path
        contents
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
      reconcileDurableRecordStaging
        "durable record publication"
        authorizedRoot
        authorizedPath
      existing <-
        observeAuthorizedPathStatus
          "durable record publication"
          authorizedRoot
          authorizedPath
      case existing of
        Just _ ->
          ioError
            (userError ("durable provisioning record already exists: " <> authorizedPath))
        Nothing ->
          publishDurableRecordBytes
            DurableRecordFirstPublication
            authorizedRoot
            authorizedPath
            contents
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
      reconcileDurableRecordStaging
        "durable record recovery"
        authorizedRoot
        authorizedPath
      observed <-
        observeAuthorizedPathStatus
          "durable record recovery"
          authorizedRoot
          authorizedPath
      case observed of
        Nothing -> pure Nothing
        Just status
          | Posix.isRegularFile status
              && not (Posix.isSymbolicLink status) -> do
              contents <-
                readAuthorizedRegularFile
                  "durable record recovery"
                  authorizedRoot
                  authorizedPath
                  (fromIntegral maximumDurableProvisioningRecordBytes)
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
      requireDurableRecordEntry
        "durable record replacement"
        authorizedRoot
        authorizedPath
      reconcileDurableRecordStaging
        "durable record replacement"
        authorizedRoot
        authorizedPath
      publishDurableRecordBytes
        DurableRecordReplacement
        authorizedRoot
        authorizedPath
        contents
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
      requireDurableRecordEntry
        "durable record retirement"
        authorizedRoot
        authorizedPath
      removeAuthorizedLeafThroughKernel
        "durable record retirement"
        authorizedRoot
        authorizedPath
      reconcileDurableRecordStaging
        "durable record retirement"
        authorizedRoot
        authorizedPath
      validateWriterRootIdentity "durable record retirement" authorizedRoot

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

-- | Whether a durable record is being published for the first time or is
-- replacing an existing one.
--
-- The two differ in the precondition the atomic publish step enforces at the
-- destination, so naming them keeps that choice at the call site instead of in
-- a positional 'Bool'.
data DurableRecordPublication
  = DurableRecordFirstPublication
  | DurableRecordReplacement
  deriving (Eq, Show)

-- | Discard a leftover staging entry beside a durable record.
--
-- The staging leaf is derived from the record's own validated leaf by
-- appending a suffix that introduces no path separator, so it is a sibling of
-- the record under the same retained parent. The superseded form appended the
-- suffix to a full pathname and then unlinked and fsynced by pathname with no
-- writer root in scope at all.
reconcileDurableRecordStaging ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
reconcileDurableRecordStaging label authorizedRoot path = do
  let stagingPath = durableRecordStagingPath path
  observed <-
    observeAuthorizedPathStatus
      (label <> " staging")
      authorizedRoot
      stagingPath
  case observed of
    Nothing -> pure ()
    Just status
      | Posix.isRegularFile status
          && not (Posix.isSymbolicLink status) ->
          removeAuthorizedLeafThroughKernel
            (label <> " staging")
            authorizedRoot
            stagingPath
      | otherwise ->
          ioError
            (userError ("durable record staging path is unsafe: " <> stagingPath))

-- | Write a durable record's bytes to a staging sibling and publish it
-- atomically.
--
-- Both the staging create and its failure-path removal are anchored on the
-- retained parent descriptor, and the publish step is the kernel's sibling
-- rename, which is the only descriptor-anchored rename available. The staging
-- file is fsynced before the rename and the parent afterwards, so the record
-- is durable at the name a reader will look for.
publishDurableRecordBytes ::
  DurableRecordPublication ->
  AuthorizedWriterRoot ->
  FilePath ->
  ByteString.ByteString ->
  IO ()
publishDurableRecordBytes publication authorizedRoot path contents = do
  let stagingPath = durableRecordStagingPath path
  recordComponents <-
    authorizedWriterRelativeComponents
      (label <> " record")
      authorizedRoot
      path
  stagingComponents <-
    authorizedWriterRelativeComponents
      (label <> " staging")
      authorizedRoot
      stagingPath
  unless
    (init recordComponents == init stagingComponents)
    (ioError (userError (label <> " staging is not a sibling of its record")))
  onExceptionPreservingPrimary
    ( do
        writeAuthorizedRegularFile
          (label <> " staging")
          authorizedRoot
          stagingPath
          contents
        case publication of
          DurableRecordFirstPublication -> pure ()
          DurableRecordReplacement ->
            requireDurableRecordEntry label authorizedRoot path
        runAuthorizedFilesystemMutation
          (label <> " publication")
          authorizedRoot
          ( durableRecordPublishMutation
              publication
              (authorizedWriterMutationRoot authorizedRoot)
              (init stagingComponents)
              (last stagingComponents)
              (last recordComponents)
          )
    )
    ( removeAuthorizedLeafThroughKernel
        (label <> " staging rollback")
        authorizedRoot
        stagingPath
    )
  where
    label = "durable record"

-- | The atomic publish step for each publication kind.
durableRecordPublishMutation ::
  DurableRecordPublication ->
  Subprocess.ProvisioningMutationRoot ->
  [FilePath] ->
  FilePath ->
  FilePath ->
  Either
    Subprocess.ProvisioningFilesystemMutationOutcome
    Subprocess.ProvisioningFilesystemMutation
durableRecordPublishMutation publication mutationRoot parentComponents =
  case publication of
    DurableRecordFirstPublication ->
      Subprocess.provisioningRenameSiblingRegularFile
        mutationRoot
        parentComponents
    DurableRecordReplacement ->
      Subprocess.provisioningReplaceSiblingRegularFile
        mutationRoot
        parentComponents

-- | Require that an authorized path names a real regular file, observed through
-- the retained parent descriptor rather than by re-resolving the pathname.
requireDurableRecordEntry ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
requireDurableRecordEntry label authorizedRoot path = do
  observed <- observeAuthorizedPathStatus label authorizedRoot path
  unless
    ( maybe
        False
        (\status -> Posix.isRegularFile status && not (Posix.isSymbolicLink status))
        observed
    )
    (ioError (userError ("durable provisioning record is unsafe: " <> path)))

-- | Remove one leaf under an authorized writer root through the mutation
-- kernel.
--
-- @unix-2.8.8.0@ exposes no public @unlinkat@ and @foreign import@ is
-- forbidden, so the kernel -- which @fchdir@s into the retained parent and
-- names one CWD-relative leaf -- is the only descriptor-anchored removal
-- available. Removing an absent leaf succeeds, so this is idempotent and safe
-- on a rollback path.
removeAuthorizedLeafThroughKernel ::
  String ->
  AuthorizedWriterRoot ->
  FilePath ->
  IO ()
removeAuthorizedLeafThroughKernel label authorizedRoot path = do
  components <-
    authorizedWriterRelativeComponents label authorizedRoot path
  runAuthorizedFilesystemMutation
    label
    authorizedRoot
    ( Subprocess.provisioningRemoveTreeLeaf
        (authorizedWriterMutationRoot authorizedRoot)
        (init components)
        (last components)
    )

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
    readProvisioningDescriptorChunk
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

-- | Make one already-retained directory descriptor durable.
--
-- This is the only fsync form in this module. The superseded @FilePath@ form
-- re-resolved the directory it was asked to make durable, so a parent swapped
-- at that moment was fsynced instead of the directory the caller had just
-- mutated -- the effect and its durability proof named different objects. Every
-- caller now holds the descriptor it mutated through and hands that exact
-- object here.
synchroniseProvisioningDescriptor :: Fd -> IO ()
synchroniseProvisioningDescriptor descriptor = do
  status <- Posix.getFdStatus descriptor
  unless
    (Posix.isDirectory status)
    (ioError (userError "fsync descriptor is not a directory"))
  fileSynchronise descriptor

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

provisioningMakeExecutable ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningMakeExecutable (EngineWriter _ _ authorizedRoot) path =
  ProvisioningSession $ do
    setAuthorizedLeafExecutable
      "engine executable mutation"
      authorizedRoot
      path
    validateWriterRootIdentity "engine executable mutation" authorizedRoot

provisioningReconcileArtifactRoot ::
  EngineWriter w s q ->
  FilePath ->
  ProvisioningSession s ()
provisioningReconcileArtifactRoot
  writer@(EngineWriter authority _recovered authorizedRoot)
  installRoot =
    ProvisioningSession $ do
      authorizedInstallRoot <-
        authorizedWriterPath
          "artifact reconciliation"
          authorizedRoot
          installRoot
      ArtifactInternal.reconcileEngineArtifactRoot
        authority
        (provisioningArtifactRootMutator writer)
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

-- | Create the in-project Poetry environment under the held project writer.
--
-- Poetry resolves its target environment from the running interpreter when the
-- project has none of its own, and a sealed bounded run points @PYTHONHOME@ at
-- the sealed copy of Poetry's environment. A first install therefore writes the
-- engine's whole framework payload into the ephemeral generation, which both
-- discards the environment the readiness marker requires and grows the
-- generation past the bound its retirement walk admits. Creating the project
-- environment first makes the choice the project's.
createPoetryProjectVenv ::
  ProjectWriter p s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  ProvisioningSession s ProvisioningOutcome
createPoetryProjectVenv
  (ProjectWriter _ projectRoot)
  grant
  deadline =
    runProvisioningCommandInWriter
      projectRoot
      []
      grant
      deadline
      ( Internal.CreatePoetryProjectVenv
          (authorizedWriterCanonicalRoot projectRoot)
      )

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
      (StableCopySourceExactContent (resolvedExecutableDigest venvIdentity))
      authorizedRoot
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
    let requirementsPath =
          poetryHome </> Internal.poetryBootstrapRequirementsRelativePath
        install =
          runProvisioningCommandWithExecutableInWriter
            homeRoot
            components
            grant
            deadline
            identity
            []
            []
            (Internal.InstallPoetryBootstrap poetryHome)
    ProvisioningSession $
      finallyPreservingPrimary
        ( do
            writeAuthorizedRegularFile
              "Poetry bootstrap requirements"
              homeRoot
              requirementsPath
              ( TextEncoding.encodeUtf8
                  (Text.pack (unlines Internal.pinnedPoetryBootstrapRequirements))
              )
            validateWriterRootIdentity
              "Poetry bootstrap requirements"
              homeRoot
            case install of
              ProvisioningSession action -> action
        )
        ( do
            removeAuthorizedLeafThroughKernel
              "Poetry bootstrap requirements cleanup"
              homeRoot
              requirementsPath
            validateWriterRootIdentity
              "Poetry bootstrap requirements cleanup"
              homeRoot
        )

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

extractAudiverisJavaCppNatives ::
  EngineWriter w s q ->
  ProvisioningGrant s ->
  ProvisioningDeadline ->
  FilePath ->
  ProvisioningSession s ProvisioningOutcome
extractAudiverisJavaCppNatives
  (EngineWriter _ _ engineRoot)
  grant
  deadline
  candidateRoot = do
    authorizedCandidate <-
      ProvisioningSession
        (authorizedWriterPath "Audiveris JavaCPP candidate" engineRoot candidateRoot)
    let appRoot = authorizedCandidate </> "Audiveris.app"
        javaExecutable =
          appRoot
            </> "Contents"
            </> "runtime"
            </> "Contents"
            </> "Home"
            </> "bin"
            </> "java"
    javaIdentity <-
      ProvisioningSession (resolveExactExecutableIdentity javaExecutable)
    appIdentity <-
      ProvisioningSession
        ( resolvePackageClosureIdentity
            Internal.ProvisioningArtifactRootClosure
            appRoot
        )
    components <-
      ProvisioningSession
        ( authorizedWriterRelativeComponents
            "Audiveris JavaCPP extraction working directory"
            engineRoot
            authorizedCandidate
        )
    runProvisioningCommandWithExecutableInWriter
      engineRoot
      components
      grant
      deadline
      javaIdentity
      [appIdentity]
      []
      (Internal.ExtractAudiverisJavaCppNatives authorizedCandidate)

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
