{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ImportQualifiedPost #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiWayIf #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE TypeApplications #-}

-- | Package-internal engine-artifact transaction and content identity.
--
-- A candidate is complete only after its manifest names the digest of the
-- actual hydrated payload tree. Activation uses sibling renames and retains a
-- previously complete root until the replacement has been revalidated at its
-- final path.
module Infernix.Engines.Artifact.Internal
  ( ResolvedArtifactProvenance (..),
    EngineArtifactManifest (..),
    engineArtifactManifestPath,
    engineArtifactPreviousRoot,
    engineArtifactTempRoot,
    renderEngineArtifactManifest,
    decodeEngineArtifactManifest,
    ArtifactSnapshotBoundary (..),
    maximumArtifactSnapshotEntries,
    maximumArtifactSnapshotBytes,
    maximumArtifactSnapshotDepth,
    validateArtifactSnapshotBounds,
    renderArtifactSnapshotRecord,
    digestEngineArtifactPayload,
    digestEngineArtifactPayloadWithObserver,
    digestEngineArtifactImageClosureForTest,
    observeNativeArtifactTargetEvidence,
    validateNativeArtifactTargetEvidence,
    portableImageTargetEvidenceForTest,
    validateEngineArtifactRootAt,
    manifestFingerprint,
    ArtifactResolution (..),
    NativeArtifactIdentity,
    parseNativeArtifactIdentity,
    ArtifactRuntimeExpectation,
    appleArtifactRuntimeExpectation,
    linuxArtifactRuntimeExpectation,
    currentArtifactRecipeFingerprint,
    engineArtifactGenerationFingerprint,
    rederiveArtifactGenerationFingerprint,
    ArtifactPhase (..),
    ArtifactOutputStream (..),
    ArtifactProcessOutcome (..),
    ArtifactTerminalOutcome (..),
    ArtifactLaunchRequest,
    artifactLaunchInstallRoot,
    artifactLaunchEntrypoint,
    artifactLaunchLeadingArguments,
    ArtifactLauncher,
    artifactLauncher,
    ArtifactPreLaunchFixture,
    noArtifactPreLaunchFixture,
    overwriteFileBeforeLaunch,
    withFirstValidatedEngineArtifact,
    withFirstValidatedEngineArtifactUnderPreLaunchFixture,
    revalidateValidatedEngineArtifact,
    validateEngineArtifactHelperLease,
    validateArtifactGenerationPayloadLease,
    reconcileEngineArtifactRoot,
    ArtifactActivationBoundary (..),
    ArtifactCleanupBoundary (..),
    PendingArtifactActivation,
    CommittedArtifactActivation,
    ArtifactRootMutation (..),
    ArtifactRootMutator (..),
    runArtifactRootMutation,
    artifactRootMutatorForTest,
    beginEngineArtifactActivationUnderGeneration,
    pendingArtifactActivationManifest,
    pendingArtifactActivationPriorManifest,
    commitEngineArtifactActivationUnderGeneration,
    rollbackEngineArtifactActivationUnderGeneration,
    committedArtifactActivationManifest,
    committedArtifactActivationPriorManifest,
    activateEngineArtifactAfterCheck,
    installEngineArtifactRoot,
    installEngineArtifactRootWithExpectedDigest,
    installEngineArtifactRootWithObserverForTest,
    installEngineArtifactRootWithPendingActionForTest,
    installEngineArtifactRootWithCleanupObserverForTest,
  )
where

import Control.Exception
  ( IOException,
    SomeException,
    evaluate,
    mask,
    throwIO,
    try,
  )
import Control.Monad (foldM, unless, void, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson
  ( FromJSON (parseJSON),
    ToJSON (toJSON),
    eitherDecode,
    encode,
    object,
    withObject,
    (.!=),
    (.:),
    (.:?),
    (.=),
  )
import Data.Bits ((.&.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.ByteString.Lazy qualified as LazyByteString
import Data.List qualified as List
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import Foreign.C.Error (Errno (Errno), eLOOP)
import GHC.IO.Exception qualified as GHCIOException
import Infernix.Engines.Artifact.Capability
  ( ArtifactLaunchRequest,
    ArtifactLauncher,
    ArtifactOutputStream (..),
    ArtifactPhase (..),
    ArtifactPreLaunchFixture,
    ArtifactProcessOutcome (..),
    ArtifactRun,
    ArtifactTerminalOutcome (..),
    ValidatedEngineArtifact (..),
    artifactLaunchEntrypoint,
    artifactLaunchInstallRoot,
    artifactLaunchLeadingArguments,
    artifactLauncher,
    noArtifactPreLaunchFixture,
    overwriteFileBeforeLaunch,
  )
import Infernix.Engines.Artifact.Capability qualified as Capability
import Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    nativeArtifactAdapterId,
    parseNativeArtifactIdentity,
  )
import Infernix.Engines.Artifact.Loader qualified as Loader
import Infernix.Engines.Artifact.Recipe
  ( nativeArtifactRecipeFingerprint,
  )
import Infernix.Engines.Artifact.Snapshot qualified as Snapshot
import Infernix.Engines.Artifact.Target
  ( NativeArtifactLoaderEvidence (..),
    NativeArtifactLoaderFileEvidence (..),
    NativeArtifactLoaderObjectEvidence (..),
    NativeArtifactLoaderResolutionEvidence (..),
    NativeArtifactTarget,
    NativeArtifactTargetClosureEvidence (..),
    NativeArtifactTargetEvidence (..),
    NativeArtifactTargetExecutableEvidence (..),
    nativeArtifactTarget,
    nativeArtifactTargetEvidenceFingerprint,
    nativeArtifactTargetExecutable,
    nativeArtifactTargetFingerprint,
    nativeArtifactTargetImmutableClosureRoots,
    nativeArtifactTargetIsInstalled,
    nativeArtifactTargetLeadingArguments,
  )
import Infernix.Engines.MaterializationLock
  ( withTryEngineArtifactReadLock,
  )
import Infernix.Engines.MaterializationLock.Internal
  ( ArtifactGenerationMutationAuthority,
    MaterializationAuthority,
    artifactGenerationLease,
    artifactGenerationLeasePath,
    materializationAuthorityDeviceId,
    materializationAuthorityFileId,
    materializationAuthorityMode,
    materializationAuthorityRoot,
  )
import Infernix.Error
  ( finallyPreservingPrimary,
  )
import System.Directory
  ( canonicalizePath,
    makeAbsolute,
    removeDirectoryRecursive,
    renameDirectory,
  )
import System.FilePath
  ( dropTrailingPathSeparator,
    isAbsolute,
    makeRelative,
    normalise,
    splitDirectories,
    takeDirectory,
    takeFileName,
    (</>),
  )
import System.IO.Error (isDoesNotExistError, isEOFError)
import System.Info qualified as SystemInfo
import System.Posix.Directory
  ( closeDirStream,
    readDirStream,
    rewindDirStream,
  )
import System.Posix.Directory.Fd (unsafeOpenDirStreamFd)
import System.Posix.Files
  ( FileStatus,
    deviceID,
    fileID,
    fileMode,
    fileSize,
    getFdStatus,
    getSymbolicLinkStatus,
    isDirectory,
    isRegularFile,
    isSymbolicLink,
    modificationTimeHiRes,
    readSymbolicLink,
    statusChangeTimeHiRes,
  )
import System.Posix.IO
  ( FdOption (CloseOnExec),
    OpenFileFlags (cloexec, directory, nofollow, nonBlock),
    OpenMode (ReadOnly),
    closeFd,
    defaultFileFlags,
    dup,
    openFd,
    openFdAt,
    setFdOption,
  )
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Types (ByteCount, Fd)
import System.Posix.Unistd (fileSynchronise)

data ResolvedArtifactProvenance = ResolvedArtifactProvenance
  { resolvedProvenanceName :: !Text,
    resolvedProvenanceVersion :: !Text,
    resolvedProvenanceSource :: !Text
  }
  deriving (Eq, Show)

instance ToJSON ResolvedArtifactProvenance where
  toJSON provenance =
    object
      [ "name" .= resolvedProvenanceName provenance,
        "version" .= resolvedProvenanceVersion provenance,
        "source" .= resolvedProvenanceSource provenance
      ]

instance FromJSON ResolvedArtifactProvenance where
  parseJSON =
    withObject "ResolvedArtifactProvenance" $ \value ->
      ResolvedArtifactProvenance
        <$> value .: "name"
        <*> value .: "version"
        <*> value .: "source"

data EngineArtifactManifest = EngineArtifactManifest
  { manifestAdapterId :: !Text,
    manifestEngineName :: !Text,
    manifestSubstrate :: !Text,
    manifestArchitecture :: !Text,
    manifestArtifactKind :: !Text,
    manifestSourceRef :: !Text,
    manifestEngineVersion :: !Text,
    manifestPythonVersion :: !(Maybe Text),
    manifestRuntimeVersion :: !Text,
    manifestResolvedProvenance :: ![ResolvedArtifactProvenance],
    manifestRecipeFingerprint :: !Text,
    manifestDigest :: !Text,
    manifestGenerationFingerprint :: !Text,
    manifestMinioObjectKey :: !Text,
    manifestLocalInstallRoot :: !FilePath,
    manifestTargetContractFingerprint :: !Text,
    manifestImageTargetEvidence :: !(Maybe NativeArtifactTargetEvidence)
  }
  deriving (Eq, Show)

instance ToJSON EngineArtifactManifest where
  toJSON manifest =
    object
      [ "adapterId" .= manifestAdapterId manifest,
        "engineName" .= manifestEngineName manifest,
        "substrate" .= manifestSubstrate manifest,
        "architecture" .= manifestArchitecture manifest,
        "artifactKind" .= manifestArtifactKind manifest,
        "sourceRef" .= manifestSourceRef manifest,
        "engineVersion" .= manifestEngineVersion manifest,
        "pythonVersion" .= manifestPythonVersion manifest,
        "runtimeVersion" .= manifestRuntimeVersion manifest,
        "resolvedProvenance" .= manifestResolvedProvenance manifest,
        "recipeFingerprint" .= manifestRecipeFingerprint manifest,
        "digest" .= manifestDigest manifest,
        "generationFingerprint" .= manifestGenerationFingerprint manifest,
        "minioObjectKey" .= manifestMinioObjectKey manifest,
        "localInstallRoot" .= manifestLocalInstallRoot manifest,
        "targetContractFingerprint"
          .= manifestTargetContractFingerprint manifest,
        "imageTargetEvidence" .= manifestImageTargetEvidence manifest
      ]

instance FromJSON EngineArtifactManifest where
  parseJSON =
    withObject "EngineArtifactManifest" $ \value ->
      EngineArtifactManifest
        <$> value .: "adapterId"
        <*> value .: "engineName"
        <*> value .: "substrate"
        <*> value .: "architecture"
        <*> value .: "artifactKind"
        <*> value .: "sourceRef"
        <*> value .: "engineVersion"
        <*> value .: "pythonVersion"
        <*> value .: "runtimeVersion"
        <*> value .:? "resolvedProvenance" .!= []
        <*> value .: "recipeFingerprint"
        <*> value .: "digest"
        <*> value .:? "generationFingerprint" .!= ""
        <*> value .: "minioObjectKey"
        <*> value .: "localInstallRoot"
        <*> value .: "targetContractFingerprint"
        <*> value .: "imageTargetEvidence"

engineArtifactTempRoot :: FilePath -> FilePath
engineArtifactTempRoot installRoot = installRoot <> ".tmp"

engineArtifactPreviousRoot :: FilePath -> FilePath
engineArtifactPreviousRoot installRoot = installRoot <> ".previous"

engineArtifactManifestPath :: FilePath -> FilePath
engineArtifactManifestPath installRoot =
  installRoot </> "engine-artifact.json"

renderEngineArtifactManifest ::
  EngineArtifactManifest ->
  LazyByteString.ByteString
renderEngineArtifactManifest = encode

decodeEngineArtifactManifest ::
  LazyByteString.ByteString ->
  Either String EngineArtifactManifest
decodeEngineArtifactManifest = eitherDecode

data ArtifactSnapshotBoundary
  = ArtifactSnapshotDirectoryListed !FilePath
  | ArtifactSnapshotEntryOpened !FilePath
  | ArtifactSnapshotFileChunkRead !FilePath !Integer
  deriving (Eq, Show)

maximumArtifactSnapshotEntries :: Int
maximumArtifactSnapshotEntries = 100000

maximumArtifactSnapshotBytes :: Integer
maximumArtifactSnapshotBytes = 4 * 1024 * 1024 * 1024

maximumArtifactSnapshotDepth :: Int
maximumArtifactSnapshotDepth = 64

validateArtifactSnapshotBounds ::
  Int ->
  Integer ->
  Int ->
  Either String ()
validateArtifactSnapshotBounds entryCount payloadBytes depth
  | entryCount < 0 =
      Left "engine artifact snapshot entry count is negative"
  | entryCount > maximumArtifactSnapshotEntries =
      Left
        ( "engine artifact snapshot exceeds "
            <> show maximumArtifactSnapshotEntries
            <> " entries"
        )
  | payloadBytes < 0 =
      Left "engine artifact snapshot byte count is negative"
  | payloadBytes > maximumArtifactSnapshotBytes =
      Left
        ( "engine artifact snapshot exceeds "
            <> show maximumArtifactSnapshotBytes
            <> " payload bytes"
        )
  | depth < 0 =
      Left "engine artifact snapshot depth is negative"
  | depth > maximumArtifactSnapshotDepth =
      Left
        ( "engine artifact snapshot exceeds depth "
            <> show maximumArtifactSnapshotDepth
        )
  | otherwise = Right ()

data ArtifactSnapshotState = ArtifactSnapshotState
  { snapshotDigestContext :: !SHA256.Ctx,
    snapshotEntryCount :: !Int,
    snapshotPayloadBytes :: !Integer
  }

digestEngineArtifactPayload :: FilePath -> IO Text
digestEngineArtifactPayload =
  digestEngineArtifactPayloadWithObserver (const (pure ()))

observeNativeArtifactTargetEvidence ::
  FilePath ->
  NativeArtifactTarget ->
  IO NativeArtifactTargetEvidence
observeNativeArtifactTargetEvidence installRoot target = do
  executableEvidence <-
    observeNativeArtifactTargetExecutable
      ( if nativeArtifactTargetIsInstalled target
          then Just installRoot
          else Nothing
      )
      (nativeArtifactTargetExecutable installRoot target)
  let closureRoots =
        map
          normalise
          (nativeArtifactTargetImmutableClosureRoots installRoot target)
  unless
    ( not (null closureRoots)
        && length closureRoots <= maximumNativeTargetClosureRoots
        && length (List.nub closureRoots) == length closureRoots
    )
    (ioError (userError "native artifact target closure roots are invalid"))
  closureEvidence <-
    mapM observeNativeArtifactTargetClosure closureRoots
  loaderEvidence <-
    observeTargetLoaderEvidence target executableEvidence closureRoots
  pure
    NativeArtifactTargetEvidence
      { targetEvidenceContractFingerprint =
          nativeArtifactTargetFingerprint target,
        targetEvidenceExecutable = executableEvidence,
        targetEvidenceClosures = closureEvidence,
        targetEvidenceLoader = loaderEvidence
      }

-- | The loader closure for an image target.
--
-- An installed Apple target carries none: its payload root is copied whole and
-- already digested, its runtime closure is vendored into that root during
-- hydration, and its loader provenance is proven at run time by the installed
-- smoke's @DYLD_PRINT_LIBRARIES@ audit. @validateEngineArtifactRootAt@ rejects
-- an Apple manifest that carries image-target evidence at all, so producing it
-- here would make every Apple root unvalidatable.
--
-- An image target is the opposite case. Its executable and closure roots live
-- in the immutable image, but the loader it names through @PT_INTERP@, the
-- resolution metadata in @\/etc\/ld.so.cache@, and every system library it
-- reaches through @DT_NEEDED@ live outside those roots and were previously
-- bound by nothing at all.
observeTargetLoaderEvidence ::
  NativeArtifactTarget ->
  NativeArtifactTargetExecutableEvidence ->
  [FilePath] ->
  IO (Maybe NativeArtifactLoaderEvidence)
observeTargetLoaderEvidence target executableEvidence closureRoots
  | nativeArtifactTargetIsInstalled target = pure Nothing
  | otherwise =
      Just
        <$> Loader.observeNativeArtifactLoaderEvidence
          (targetExecutableCanonicalPath executableEvidence)
          closureRoots

validateNativeArtifactTargetEvidence ::
  FilePath ->
  NativeArtifactTarget ->
  NativeArtifactTargetEvidence ->
  IO ()
validateNativeArtifactTargetEvidence installRoot target expected = do
  observed <- observeNativeArtifactTargetEvidence installRoot target
  unless
    ( portableImageTargetEvidenceForTest observed
        == portableImageTargetEvidenceForTest expected
    )
    $ ioError
      (userError "native artifact direct target or runtime closure identity changed")

-- OCI unpack assigns fresh device/inode identities on each container rootfs.
-- Observation still uses those identities to prove every descriptor-stable
-- read, but persisted image evidence must compare the portable identity:
-- closed path, type/mode/size, digest, ELF metadata, and loader edges.
portableImageTargetEvidenceForTest :: NativeArtifactTargetEvidence -> NativeArtifactTargetEvidence
portableImageTargetEvidenceForTest evidence =
  evidence
    { targetEvidenceExecutable = portableExecutable (targetEvidenceExecutable evidence),
      targetEvidenceClosures = map portableClosure (targetEvidenceClosures evidence),
      targetEvidenceLoader = portableLoader <$> targetEvidenceLoader evidence
    }
  where
    portableExecutable executable =
      executable
        { targetExecutableConfiguredDeviceId = 0,
          targetExecutableConfiguredFileId = 0,
          targetExecutableCanonicalDeviceId = 0,
          targetExecutableCanonicalFileId = 0
        }
    portableClosure closure =
      closure
        { targetClosureDeviceId = 0,
          targetClosureFileId = 0
        }
    portableLoader loader =
      loader
        { loaderEvidenceCache =
            if any loaderResolutionUsedCache (loaderEvidenceResolutions loader)
              then portableLoaderFile <$> loaderEvidenceCache loader
              else Nothing,
          loaderEvidenceObjects = map portableLoaderObject (loaderEvidenceObjects loader)
        }
    portableLoaderFile loaderFile =
      loaderFile
        { loaderFileConfiguredDeviceId = 0,
          loaderFileConfiguredFileId = 0,
          loaderFileCanonicalDeviceId = 0,
          loaderFileCanonicalFileId = 0
        }
    portableLoaderObject loaderObject =
      loaderObject
        { loaderObjectConfiguredDeviceId = 0,
          loaderObjectConfiguredFileId = 0,
          loaderObjectCanonicalDeviceId = 0,
          loaderObjectCanonicalFileId = 0
        }

maximumNativeTargetClosureRoots :: Int
maximumNativeTargetClosureRoots = 8

maximumNativeTargetExecutableBytes :: Integer
maximumNativeTargetExecutableBytes = 512 * 1024 * 1024

observeNativeArtifactTargetExecutable ::
  Maybe FilePath ->
  FilePath ->
  IO NativeArtifactTargetExecutableEvidence
observeNativeArtifactTargetExecutable maybeInstalledRoot configuredPath = do
  unless (isAbsolute configuredPath && '\0' `notElem` configuredPath) $
    ioError (userError "native artifact target executable path is invalid")
  configuredStatus <-
    case maybeInstalledRoot of
      Nothing -> getSymbolicLinkStatus configuredPath
      Just _ ->
        requireOwnedExecutableRegularFileStatus
          "installed native artifact target"
          configuredPath
  canonicalPath <- canonicalizePath configuredPath
  canonicalStatus <- getSymbolicLinkStatus canonicalPath
  mapM_
    ( \installedRoot -> do
        installedRootStatus <-
          requireOwnedDirectory
            "installed native artifact root"
            installedRoot
        canonicalInstalledRoot <- canonicalizePath installedRoot
        finalInstalledRootStatus <- getSymbolicLinkStatus installedRoot
        unless
          ( stableFileStatusMatches
              installedRootStatus
              finalInstalledRootStatus
              && not (isSymbolicLink finalInstalledRootStatus)
              && pathIsWithin
                canonicalInstalledRoot
                canonicalPath
          )
          ( ioError
              ( userError
                  "installed native artifact target escapes its exact artifact root"
              )
          )
    )
    maybeInstalledRoot
  unless
    ( isRegularFile canonicalStatus
        && not (isSymbolicLink canonicalStatus)
        && fileMode canonicalStatus .&. 0o111 /= 0
        && toInteger (fileSize canonicalStatus)
          <= maximumNativeTargetExecutableBytes
    )
    (ioError (userError "native artifact target is not a bounded regular executable"))
  digest <-
    withStableRegularFileDescriptor
      canonicalPath
      canonicalStatus
      ( \descriptor openedStatus -> do
          (digestContext, observedBytes) <-
            hashDescriptorAtExactSize
              (const (pure ()))
              canonicalPath
              SHA256.init
              descriptor
              (toInteger (fileSize openedStatus))
          unless
            (observedBytes == toInteger (fileSize openedStatus))
            (ioError (userError "native artifact target executable size changed"))
          pure
            ( "sha256:"
                <> TextEncoding.decodeUtf8
                  (Base16.encode (SHA256.finalize digestContext))
            )
      )
  finalConfiguredStatus <- getSymbolicLinkStatus configuredPath
  finalCanonicalPath <- canonicalizePath configuredPath
  finalCanonicalStatus <- getSymbolicLinkStatus canonicalPath
  unless
    ( stableFileStatusMatches configuredStatus finalConfiguredStatus
        && normalise canonicalPath == normalise finalCanonicalPath
        && stableFileStatusMatches canonicalStatus finalCanonicalStatus
    )
    (ioError (userError "native artifact target executable changed during observation"))
  pure
    NativeArtifactTargetExecutableEvidence
      { targetExecutableConfiguredPath = configuredPath,
        targetExecutableConfiguredDeviceId =
          fromIntegral (deviceID configuredStatus),
        targetExecutableConfiguredFileId =
          fromIntegral (fileID configuredStatus),
        targetExecutableConfiguredMode =
          fromIntegral (fileMode configuredStatus),
        targetExecutableConfiguredSize =
          fromIntegral (fileSize configuredStatus),
        targetExecutableCanonicalPath = canonicalPath,
        targetExecutableCanonicalDeviceId =
          fromIntegral (deviceID canonicalStatus),
        targetExecutableCanonicalFileId =
          fromIntegral (fileID canonicalStatus),
        targetExecutableCanonicalMode =
          fromIntegral (fileMode canonicalStatus),
        targetExecutableCanonicalSize =
          fromIntegral (fileSize canonicalStatus),
        targetExecutableDigest = digest
      }

pathIsWithin :: FilePath -> FilePath -> Bool
pathIsWithin root candidate =
  let relative = makeRelative (normalise root) (normalise candidate)
      components = splitDirectories relative
   in not (isAbsolute relative)
        && relative /= ".."
        && case components of
          ".." : _ -> False
          _ -> True

observeNativeArtifactTargetClosure ::
  FilePath ->
  IO NativeArtifactTargetClosureEvidence
observeNativeArtifactTargetClosure closureRoot = do
  unless (isAbsolute closureRoot && '\0' `notElem` closureRoot) $
    ioError (userError "native artifact target closure path is invalid")
  initialStatus <- requireOwnedDirectory "native artifact target closure" closureRoot
  unless (isDirectory initialStatus) $
    ioError (userError "native artifact target closure is not a directory")
  digest <- digestEngineArtifactImageClosure closureRoot
  finalStatus <- getSymbolicLinkStatus closureRoot
  unless
    ( stableFileStatusMatches initialStatus finalStatus
        && not (isSymbolicLink finalStatus)
    )
    (ioError (userError "native artifact target closure changed during observation"))
  pure
    NativeArtifactTargetClosureEvidence
      { targetClosurePath = closureRoot,
        targetClosureDeviceId = fromIntegral (deviceID finalStatus),
        targetClosureFileId = fromIntegral (fileID finalStatus),
        targetClosureMode = fromIntegral (fileMode finalStatus),
        targetClosureDigest = digest
      }

digestEngineArtifactPayloadWithObserver ::
  (ArtifactSnapshotBoundary -> IO ()) ->
  FilePath ->
  IO Text
digestEngineArtifactPayloadWithObserver observeBoundary root = do
  absoluteRoot <- makeAbsolute root
  withStableDirectoryDescriptor
    "engine artifact candidate"
    absoluteRoot
    ( \rootDescriptor _rootStatus ->
        digestEngineArtifactPayloadDescriptor
          observeBoundary
          Nothing
          absoluteRoot
          rootDescriptor
    )

digestEngineArtifactImageClosure :: FilePath -> IO Text
digestEngineArtifactImageClosure root = do
  absoluteRoot <- makeAbsolute root
  withStableDirectoryDescriptor
    "native artifact target closure"
    absoluteRoot
    ( \rootDescriptor _rootStatus ->
        digestEngineArtifactPayloadDescriptor
          (const (pure ()))
          (Just absoluteRoot)
          absoluteRoot
          rootDescriptor
    )

-- | Exercise the image-only closure policy without widening the public
-- artifact API. Image closures may contain absolute links only when their
-- targets remain inside the exact observed closure root.
digestEngineArtifactImageClosureForTest :: FilePath -> IO Text
digestEngineArtifactImageClosureForTest = digestEngineArtifactImageClosure

digestEngineArtifactPayloadDescriptor ::
  (ArtifactSnapshotBoundary -> IO ()) ->
  Maybe FilePath ->
  FilePath ->
  Fd ->
  IO Text
digestEngineArtifactPayloadDescriptor observeBoundary imageClosureRoot rootPath rootDescriptor = do
  finalState <-
    payloadDirectoryContext
      observeBoundary
      imageClosureRoot
      rootDescriptor
      rootPath
      ""
      0
      ArtifactSnapshotState
        { snapshotDigestContext =
            SHA256.update SHA256.init (ByteString8.pack "infernix-engine-payload-v2\0"),
          snapshotEntryCount = 0,
          snapshotPayloadBytes = 0
        }
  pure
    ( "sha256:"
        <> TextEncoding.decodeUtf8
          (Base16.encode (SHA256.finalize (snapshotDigestContext finalState)))
    )

payloadDirectoryContext ::
  (ArtifactSnapshotBoundary -> IO ()) ->
  Maybe FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  Int ->
  ArtifactSnapshotState ->
  IO ArtifactSnapshotState
payloadDirectoryContext
  observeBoundary
  imageClosureRoot
  directoryDescriptor
  directoryPath
  relativeDirectory
  depth
  snapshotState = do
    requireArtifactSnapshotBounds snapshotState depth
    initialDirectoryStatus <- getFdStatus directoryDescriptor
    unless (isDirectory initialDirectoryStatus) $
      ioError
        ( userError
            ( "engine artifact payload directory changed type: "
                <> displayRelativeArtifactPath relativeDirectory
            )
        )
    let remainingEntryBudget =
          maximumArtifactSnapshotEntries - snapshotEntryCount snapshotState
    entries <-
      readDirectoryEntriesFromDescriptor
        remainingEntryBudget
        directoryDescriptor
    let reservedState =
          snapshotState
            { snapshotEntryCount =
                snapshotEntryCount snapshotState + length entries
            }
    requireArtifactSnapshotBounds reservedState depth
    observeBoundary (ArtifactSnapshotDirectoryListed relativeDirectory)
    finalState <-
      foldM
        ( payloadEntryContext
            observeBoundary
            imageClosureRoot
            directoryDescriptor
            directoryPath
            relativeDirectory
            depth
        )
        reservedState
        entries
    finalDirectoryStatus <- getFdStatus directoryDescriptor
    unless (stableFileStatusMatches initialDirectoryStatus finalDirectoryStatus) $
      ioError
        ( userError
            ( "engine artifact payload directory changed while reading: "
                <> displayRelativeArtifactPath relativeDirectory
            )
        )
    pure finalState

payloadEntryContext ::
  (ArtifactSnapshotBoundary -> IO ()) ->
  Maybe FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  Int ->
  ArtifactSnapshotState ->
  FilePath ->
  IO ArtifactSnapshotState
payloadEntryContext
  observeBoundary
  imageClosureRoot
  parentDescriptor
  parentPath
  relativeDirectory
  depth
  snapshotState
  entryName = do
    validateEntryName entryName
    let relativePath =
          if null relativeDirectory
            then entryName
            else relativeDirectory </> entryName
    parentStatusBefore <- getFdStatus parentDescriptor
    childResolution <-
      withStableChildDescriptor
        relativePath
        parentDescriptor
        entryName
        ( \childDescriptor openedStatus ->
            if null relativeDirectory && entryName == "engine-artifact.json"
              then do
                unless (isRegularFile openedStatus) $
                  ioError
                    ( userError
                        "engine artifact manifest must be a regular file"
                    )
                pure snapshotState
              else
                if isRegularFile openedStatus
                  then do
                    observeBoundary (ArtifactSnapshotEntryOpened relativePath)
                    let declaredBytes = toInteger (fileSize openedStatus)
                    when (declaredBytes < 0) $
                      ioError
                        ( userError
                            ( "engine artifact payload file has a negative declared size: "
                                <> relativePath
                            )
                        )
                    contentState <-
                      accountArtifactSnapshotBytes
                        snapshotState
                        depth
                        declaredBytes
                    (contentsContext, verifiedBytes) <-
                      hashDescriptorAtExactSize
                        observeBoundary
                        relativePath
                        SHA256.init
                        childDescriptor
                        declaredBytes
                    let contentsDigest =
                          TextEncoding.decodeUtf8
                            (Base16.encode (SHA256.finalize contentsContext))
                    pure
                      contentState
                        { snapshotDigestContext =
                            SHA256.update
                              (snapshotDigestContext contentState)
                              ( canonicalRecord
                                  "file"
                                  relativePath
                                  openedStatus
                                  verifiedBytes
                                  contentsDigest
                              )
                        }
                  else
                    if isDirectory openedStatus
                      then do
                        observeBoundary (ArtifactSnapshotEntryOpened relativePath)
                        payloadDirectoryContext
                          observeBoundary
                          imageClosureRoot
                          childDescriptor
                          (parentPath </> entryName)
                          relativePath
                          (depth + 1)
                          snapshotState
                            { snapshotDigestContext =
                                SHA256.update
                                  (snapshotDigestContext snapshotState)
                                  (canonicalRecord "directory" relativePath openedStatus 0 "")
                            }
                      else
                        ioError
                          ( userError
                              ( "engine artifact payload contains an unsupported file type: "
                                  <> relativePath
                              )
                          )
        )
    result <-
      case childResolution of
        ChildDescriptorOpened openedResult ->
          pure openedResult
        ChildDescriptorSymlink
          | null relativeDirectory && entryName == "engine-artifact.json" ->
              ioError
                (userError "engine artifact manifest must be a regular file")
          | otherwise ->
              digestStableSymlink
                observeBoundary
                imageClosureRoot
                parentDescriptor
                parentPath
                relativePath
                entryName
                depth
                snapshotState
    parentStatusAfter <- getFdStatus parentDescriptor
    unless (stableFileStatusMatches parentStatusBefore parentStatusAfter) $
      ioError
        ( userError
            ( "engine artifact payload parent directory changed while reading: "
                <> displayRelativeArtifactPath relativeDirectory
            )
        )
    pure result

digestStableSymlink ::
  (ArtifactSnapshotBoundary -> IO ()) ->
  Maybe FilePath ->
  Fd ->
  FilePath ->
  FilePath ->
  FilePath ->
  Int ->
  ArtifactSnapshotState ->
  IO ArtifactSnapshotState
digestStableSymlink
  observeBoundary
  imageClosureRoot
  parentDescriptor
  parentPath
  relativePath
  entryName
  depth
  snapshotState = do
    (symlinkStatus, target) <-
      readStableArtifactSymlink
        parentDescriptor
        parentPath
        relativePath
        entryName
    validateSnapshotSymlinkTarget imageClosureRoot relativePath target
    let targetBytes =
          toInteger
            (ByteString.length (TextEncoding.encodeUtf8 (Text.pack target)))
    observeBoundary (ArtifactSnapshotEntryOpened relativePath)
    contentState <-
      accountArtifactSnapshotBytes
        snapshotState
        depth
        targetBytes
    pure
      contentState
        { snapshotDigestContext =
            SHA256.update
              (snapshotDigestContext contentState)
              ( canonicalRecord
                  "symlink"
                  relativePath
                  symlinkStatus
                  targetBytes
                  (Text.pack target)
              )
        }

readStableArtifactSymlink ::
  Fd ->
  FilePath ->
  FilePath ->
  FilePath ->
  IO (FileStatus, FilePath)
readStableArtifactSymlink
  parentDescriptor
  parentPath
  relativePath
  entryName = do
    let symlinkPath = parentPath </> entryName
    parentDescriptorStatusBefore <- getFdStatus parentDescriptor
    parentPathStatusBefore <- getSymbolicLinkStatus parentPath
    unless
      ( isDirectory parentPathStatusBefore
          && stableFileStatusMatches
            parentDescriptorStatusBefore
            parentPathStatusBefore
      )
      ( ioError
          ( userError
              ( "engine artifact payload symlink parent path changed: "
                  <> displayRelativeArtifactPath (takeDirectory relativePath)
              )
          )
      )
    listedStatus <- getSymbolicLinkStatus symlinkPath
    unless (isSymbolicLink listedStatus) $
      ioError
        (userError ("engine artifact payload symlink changed type: " <> relativePath))
    -- unix exposes no public readlinkat binding. Keep the parent directory
    -- descriptor alive and require its pathname identity before and after this
    -- bounded path-only read; the root descriptor is likewise rechecked by the
    -- enclosing snapshot region.
    target <- readSymbolicLink symlinkPath
    finalStatus <- getSymbolicLinkStatus symlinkPath
    finalTarget <- readSymbolicLink symlinkPath
    parentDescriptorStatusAfter <- getFdStatus parentDescriptor
    parentPathStatusAfter <- getSymbolicLinkStatus parentPath
    unless
      ( isDirectory parentPathStatusAfter
          && stableFileStatusMatches
            parentDescriptorStatusBefore
            parentDescriptorStatusAfter
          && stableFileStatusMatches
            parentDescriptorStatusAfter
            parentPathStatusAfter
          && isSymbolicLink finalStatus
          && stableFileStatusMatches listedStatus finalStatus
          && target == finalTarget
      )
      ( ioError
          ( userError
              ( "engine artifact payload symlink changed while reading: "
                  <> relativePath
              )
          )
      )
    pure (finalStatus, target)

accountArtifactSnapshotBytes ::
  ArtifactSnapshotState ->
  Int ->
  Integer ->
  IO ArtifactSnapshotState
accountArtifactSnapshotBytes snapshotState depth addedBytes = do
  let nextState =
        snapshotState
          { snapshotPayloadBytes =
              snapshotPayloadBytes snapshotState + addedBytes
          }
  requireArtifactSnapshotBounds nextState depth
  pure nextState

requireArtifactSnapshotBounds ::
  ArtifactSnapshotState ->
  Int ->
  IO ()
requireArtifactSnapshotBounds snapshotState depth =
  either
    (ioError . userError)
    pure
    ( validateArtifactSnapshotBounds
        (snapshotEntryCount snapshotState)
        (snapshotPayloadBytes snapshotState)
        depth
    )

withStableDirectoryDescriptor ::
  String ->
  FilePath ->
  (Fd -> FileStatus -> IO result) ->
  IO result
withStableDirectoryDescriptor label path action =
  mask $ \restore -> do
    listedStatus <- requireOwnedDirectory label path
    unless (isDirectory listedStatus) $
      ioError (userError (label <> " is not a directory: " <> path))
    descriptor <-
      openFd
        path
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True,
            directory = True
          }
    finallyPreservingPrimary
      ( do
          openedStatus <- getFdStatus descriptor
          unless
            ( isDirectory openedStatus
                && stableFileStatusMatches listedStatus openedStatus
            )
            ( ioError
                (userError (label <> " changed while opening: " <> path))
            )
          result <- restore (action descriptor openedStatus)
          finalDescriptorStatus <- getFdStatus descriptor
          finalPathStatus <- getSymbolicLinkStatus path
          unless
            ( isDirectory finalDescriptorStatus
                && not (isSymbolicLink finalPathStatus)
                && stableFileStatusMatches openedStatus finalDescriptorStatus
                && stableFileStatusMatches finalDescriptorStatus finalPathStatus
            )
            ( ioError
                (userError (label <> " changed while reading: " <> path))
            )
          pure result
      )
      (closeFd descriptor)

data ChildDescriptorResolution result
  = ChildDescriptorSymlink
  | ChildDescriptorOpened !result

withStableChildDescriptor ::
  FilePath ->
  Fd ->
  FilePath ->
  (Fd -> FileStatus -> IO result) ->
  IO (ChildDescriptorResolution result)
withStableChildDescriptor relativePath parentDescriptor entryName action =
  mask $ \restore -> do
    openResult <-
      try @IOException
        ( openFdAt
            (Just parentDescriptor)
            entryName
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                cloexec = True,
                nonBlock = True
              }
        )
    case openResult of
      Left failure
        | isNoFollowSymlinkFailure failure ->
            pure ChildDescriptorSymlink
        | otherwise -> ioError failure
      Right descriptor ->
        ChildDescriptorOpened
          <$> finallyPreservingPrimary
            ( do
                openedStatus <- getFdStatus descriptor
                result <- restore (action descriptor openedStatus)
                finalDescriptorStatus <- getFdStatus descriptor
                verificationStatus <-
                  reopenChildStatus parentDescriptor entryName relativePath
                unless
                  ( stableFileStatusMatches openedStatus finalDescriptorStatus
                      && stableFileStatusMatches
                        finalDescriptorStatus
                        verificationStatus
                  )
                  ( ioError
                      ( userError
                          ( "engine artifact payload entry changed while reading: "
                              <> relativePath
                          )
                      )
                  )
                pure result
            )
            (closeFd descriptor)

reopenChildStatus :: Fd -> FilePath -> FilePath -> IO FileStatus
reopenChildStatus parentDescriptor entryName relativePath =
  mask $ \restore -> do
    reopenResult <-
      try @IOException
        ( openFdAt
            (Just parentDescriptor)
            entryName
            ReadOnly
            defaultFileFlags
              { nofollow = True,
                cloexec = True,
                nonBlock = True
              }
        )
    case reopenResult of
      Left failure
        | isNoFollowSymlinkFailure failure ->
            ioError
              ( userError
                  ( "engine artifact payload entry became a symlink while verifying: "
                      <> relativePath
                  )
              )
        | otherwise -> ioError failure
      Right verificationDescriptor ->
        finallyPreservingPrimary
          (restore (getFdStatus verificationDescriptor))
          (closeFd verificationDescriptor)

readStableRegularFileAtBounded ::
  String ->
  Int ->
  Fd ->
  FilePath ->
  IO (FileStatus, ByteString.ByteString)
readStableRegularFileAtBounded label maximumBytes parentDescriptor entryName = do
  validateEntryName entryName
  resolution <-
    withStableChildDescriptor
      entryName
      parentDescriptor
      entryName
      ( \descriptor openedStatus -> do
          unless (isRegularFile openedStatus) $
            ioError
              (userError (label <> " must be a regular file: " <> entryName))
          contents <- readDescriptorBounded label maximumBytes descriptor
          pure (openedStatus, contents)
      )
  case resolution of
    ChildDescriptorOpened result -> pure result
    ChildDescriptorSymlink ->
      ioError (userError (label <> " must be a regular file: " <> entryName))

requireOwnedExecutableRegularFileAt ::
  String ->
  Fd ->
  FilePath ->
  IO FileStatus
requireOwnedExecutableRegularFileAt label rootDescriptor relativePath = do
  openedStatus <-
    requireOwnedPathAt
      label
      "a regular file"
      isRegularFile
      rootDescriptor
      relativePath
  unless (fileMode openedStatus .&. 0o111 /= 0) $
    ioError
      (userError (label <> " must be executable: " <> relativePath))
  pure openedStatus

requireOwnedDirectoryAt ::
  String ->
  Fd ->
  FilePath ->
  IO FileStatus
requireOwnedDirectoryAt label =
  requireOwnedPathAt label "a directory" isDirectory

requireOwnedPathAt ::
  String ->
  String ->
  (FileStatus -> Bool) ->
  Fd ->
  FilePath ->
  IO FileStatus
requireOwnedPathAt label expectedType matchesExpectedType rootDescriptor relativePath = do
  let components = filter (`notElem` ["", "."]) (splitDirectories relativePath)
  mapM_ validateEntryName components
  case components of
    [] ->
      ioError (userError (label <> " has an empty relative path"))
    _ -> descend rootDescriptor "" components
  where
    descend _parentDescriptor _parentPath [] =
      ioError (userError (label <> " has an empty relative path"))
    descend parentDescriptor parentPath [entryName] = do
      let entryPath =
            if null parentPath
              then entryName
              else parentPath </> entryName
      resolution <-
        withStableChildDescriptor
          entryPath
          parentDescriptor
          entryName
          ( \_descriptor openedStatus -> do
              unless (matchesExpectedType openedStatus) $
                ioError
                  (userError (label <> " must be " <> expectedType <> ": " <> entryPath))
              pure openedStatus
          )
      case resolution of
        ChildDescriptorOpened openedStatus -> pure openedStatus
        ChildDescriptorSymlink ->
          ioError
            (userError (label <> " must be " <> expectedType <> ": " <> entryPath))
    descend parentDescriptor parentPath (entryName : remaining) = do
      let entryPath =
            if null parentPath
              then entryName
              else parentPath </> entryName
      resolution <-
        withStableChildDescriptor
          entryPath
          parentDescriptor
          entryName
          ( \directoryDescriptor openedStatus -> do
              unless (isDirectory openedStatus) $
                ioError
                  (userError (label <> " parent changed type: " <> entryPath))
              descend directoryDescriptor entryPath remaining
          )
      case resolution of
        ChildDescriptorOpened result -> pure result
        ChildDescriptorSymlink ->
          ioError
            (userError (label <> " parent must be a directory: " <> entryPath))

readDirectoryEntriesFromDescriptor :: Int -> Fd -> IO [FilePath]
readDirectoryEntriesFromDescriptor remainingEntryBudget descriptor =
  mask $ \restore -> do
    duplicateDescriptor <- dup descriptor
    closeOnExecResult <-
      try @IOException
        (setFdOption duplicateDescriptor CloseOnExec True)
    case closeOnExecResult of
      Left failure -> do
        closeFd duplicateDescriptor
        ioError failure
      Right () -> pure ()
    directoryStream <- unsafeOpenDirStreamFd duplicateDescriptor
    finallyPreservingPrimary
      ( restore $ do
          rewindDirStream directoryStream
          entries <-
            Snapshot.collectBoundedDirectoryEntries
              remainingEntryBudget
              (readDirStream directoryStream)
          mapM_ validateEntryName entries
          pure entries
      )
      (closeDirStream directoryStream)

displayRelativeArtifactPath :: FilePath -> FilePath
displayRelativeArtifactPath relativePath =
  if null relativePath then "." else relativePath

isNoFollowSymlinkFailure :: IOException -> Bool
isNoFollowSymlinkFailure failure =
  let Errno loopErrno = eLOOP
   in GHCIOException.ioe_errno failure == Just loopErrno

hashDescriptorAtExactSize ::
  (ArtifactSnapshotBoundary -> IO ()) ->
  FilePath ->
  SHA256.Ctx ->
  Fd ->
  Integer ->
  IO (SHA256.Ctx, Integer)
hashDescriptorAtExactSize
  observeBoundary
  relativePath
  digestContext
  descriptor
  declaredBytes =
    readChunks digestContext declaredBytes 0
    where
      readChunks currentContext remainingBytes observedBytes = do
        let requestedBytes =
              fromInteger
                ( min
                    (toInteger payloadDigestChunkBytes)
                    (remainingBytes + 1)
                )
        chunk <- readDescriptorChunkSized requestedBytes descriptor
        if ByteString.null chunk
          then
            if remainingBytes == 0
              then pure (currentContext, observedBytes)
              else
                ioError
                  ( userError
                      ( "engine artifact payload file ended before its declared size: "
                          <> relativePath
                      )
                  )
          else do
            let chunkBytes = toInteger (ByteString.length chunk)
            when (chunkBytes > remainingBytes) $
              ioError
                ( userError
                    ( "engine artifact payload file exceeded its declared size while reading: "
                        <> relativePath
                    )
                )
            let nextObservedBytes = observedBytes + chunkBytes
            observeBoundary
              (ArtifactSnapshotFileChunkRead relativePath nextObservedBytes)
            readChunks
              (SHA256.update currentContext chunk)
              (remainingBytes - chunkBytes)
              nextObservedBytes

payloadDigestChunkBytes :: ByteCount
payloadDigestChunkBytes = 64 * 1024

canonicalRecord ::
  Text ->
  FilePath ->
  FileStatus ->
  Integer ->
  Text ->
  ByteString.ByteString
canonicalRecord entryType relativePath status =
  renderArtifactSnapshotRecord
    entryType
    relativePath
    (toInteger (fileMode status .&. 0o7777))

renderArtifactSnapshotRecord ::
  Text ->
  FilePath ->
  Integer ->
  Integer ->
  Text ->
  ByteString.ByteString
renderArtifactSnapshotRecord entryType relativePath modeValue sizeValue detail =
  TextEncoding.encodeUtf8
    ( Text.intercalate
        "\0"
        [ "infernix-engine-payload-record-v2",
          "type",
          entryType,
          "path",
          Text.pack relativePath,
          "mode",
          Text.pack (show modeValue),
          "size",
          Text.pack (show sizeValue),
          "detail",
          detail,
          ""
        ]
    )

validateEntryName :: FilePath -> IO ()
validateEntryName entryName =
  when
    ( null entryName
        || entryName `elem` [".", ".."]
        || '/' `elem` entryName
        || '\0' `elem` entryName
    )
    (ioError (userError ("invalid engine artifact payload entry: " <> show entryName)))

validateSymlinkTarget :: FilePath -> FilePath -> IO ()
validateSymlinkTarget relativePath target = do
  let baseDepth =
        length
          (filter (`notElem` ["", "."]) (splitDirectories (takeDirectory relativePath)))
      escapes =
        isAbsolute target
          || null target
          || '\0' `elem` target
          || pathEscapesAtDepth baseDepth (splitDirectories target)
  when escapes $
    ioError
      ( userError
          ( "engine artifact payload symlink escapes its root: "
              <> relativePath
              <> " -> "
              <> target
          )
      )

validateSnapshotSymlinkTarget ::
  Maybe FilePath ->
  FilePath ->
  FilePath ->
  IO ()
validateSnapshotSymlinkTarget imageClosureRoot relativePath target
  | isAbsolute target =
      unless
        ( '\0' `notElem` target
            && maybe False (`pathIsWithin` target) imageClosureRoot
        )
        ( ioError
            ( userError
                ( "engine artifact payload symlink escapes its root: "
                    <> relativePath
                    <> " -> "
                    <> target
                )
            )
        )
  | otherwise = validateSymlinkTarget relativePath target

pathEscapesAtDepth :: Int -> [FilePath] -> Bool
pathEscapesAtDepth _ [] = False
pathEscapesAtDepth depth (component : remaining)
  | component `elem` ["", "."] =
      pathEscapesAtDepth depth remaining
  | component == ".." =
      depth == 0 || pathEscapesAtDepth (depth - 1) remaining
  | otherwise =
      pathEscapesAtDepth (depth + 1) remaining

validateEngineArtifactRootAt ::
  FilePath ->
  FilePath ->
  IO EngineArtifactManifest
validateEngineArtifactRootAt expectedInstallRoot actualRoot = do
  absoluteActualRoot <- makeAbsolute actualRoot
  withStableDirectoryDescriptor
    "engine artifact root"
    absoluteActualRoot
    ( \rootDescriptor _rootStatus -> do
        (_manifestStatus, manifestBytes) <-
          readStableRegularFileAtBounded
            "engine artifact manifest"
            maximumManifestBytes
            rootDescriptor
            "engine-artifact.json"
        manifest <-
          either
            (ioError . userError . ("invalid engine artifact manifest: " <>))
            pure
            (decodeEngineArtifactManifest (LazyByteString.fromStrict manifestBytes))
        unless (manifestLocalInstallRoot manifest == expectedInstallRoot) $
          ioError
            ( userError
                ( "engine artifact manifest install root mismatch: expected "
                    <> expectedInstallRoot
                    <> ", observed "
                    <> manifestLocalInstallRoot manifest
                )
            )
        validateManifestContract
          ExactManifestContract
          expectedInstallRoot
          absoluteActualRoot
          rootDescriptor
          manifest
        validateExactManifestContract manifest
        observedDigest <-
          digestEngineArtifactPayloadDescriptor
            (const (pure ()))
            Nothing
            absoluteActualRoot
            rootDescriptor
        unless (manifestDigest manifest == observedDigest) $
          ioError
            ( userError
                ( "engine artifact payload digest mismatch: expected "
                    <> Text.unpack (manifestDigest manifest)
                    <> ", observed "
                    <> Text.unpack observedDigest
                )
            )
        pure manifest
    )

maximumManifestBytes :: Int
maximumManifestBytes = 1024 * 1024

-- | Which generation contract a manifest is being validated against. A
-- pre-correction declarative root predates the generation fingerprint, so the
-- legacy mode requires its absence instead of its exactness. A legacy root is
-- only ever a migration predecessor or a rollback root, never an exact one.
data ManifestContractMode
  = ExactManifestContract
  | LegacyDeclarativeManifestContract
  deriving (Eq)

validateManifestContract ::
  ManifestContractMode ->
  FilePath ->
  FilePath ->
  Fd ->
  EngineArtifactManifest ->
  IO ()
validateManifestContract
  contractMode
  expectedInstallRoot
  actualRoot
  rootDescriptor
  manifest = do
    case contractMode of
      ExactManifestContract ->
        requireNonemptyManifestField
          ("generationFingerprint", manifestGenerationFingerprint manifest)
      LegacyDeclarativeManifestContract ->
        unless
          (Text.null (manifestGenerationFingerprint manifest))
          ( ioError
              ( userError
                  "pre-correction declarative artifact claims a generation fingerprint"
              )
          )
    mapM_
      requireNonemptyManifestField
      [ ("adapterId", manifestAdapterId manifest),
        ("engineName", manifestEngineName manifest),
        ("substrate", manifestSubstrate manifest),
        ("architecture", manifestArchitecture manifest),
        ("artifactKind", manifestArtifactKind manifest),
        ("sourceRef", manifestSourceRef manifest),
        ("engineVersion", manifestEngineVersion manifest),
        ("runtimeVersion", manifestRuntimeVersion manifest),
        ("recipeFingerprint", manifestRecipeFingerprint manifest),
        ("digest", manifestDigest manifest),
        ("minioObjectKey", manifestMinioObjectKey manifest),
        ( "targetContractFingerprint",
          manifestTargetContractFingerprint manifest
        )
      ]
    mapM_ validateResolvedProvenance (manifestResolvedProvenance manifest)
    mapM_
      (\pythonVersion -> requireNonemptyManifestField ("pythonVersion", pythonVersion))
      (manifestPythonVersion manifest)
    identity <-
      maybe
        (ioError (userError "engine artifact adapter has no closed target identity"))
        pure
        (parseNativeArtifactIdentity (manifestAdapterId manifest))
    target <-
      either
        (ioError . userError)
        pure
        ( nativeArtifactTarget
            identity
            (manifestSubstrate manifest)
            (manifestArchitecture manifest)
        )
    let targetFingerprint = nativeArtifactTargetFingerprint target
    unless
      ( manifestTargetContractFingerprint manifest == targetFingerprint
          && expectedInstallRoot == manifestLocalInstallRoot manifest
      )
      (ioError (userError "engine artifact direct-target contract changed"))
    case (manifestSubstrate manifest, manifestImageTargetEvidence manifest) of
      ("apple-silicon", Nothing) ->
        void (observeNativeArtifactTargetEvidence actualRoot target)
      ("linux-native", Just expectedEvidence) -> do
        unless
          (targetEvidenceContractFingerprint expectedEvidence == targetFingerprint)
          (ioError (userError "Linux image target evidence contract changed"))
        validateNativeArtifactTargetEvidence actualRoot target expectedEvidence
      ("apple-silicon", Just _) ->
        ioError (userError "Apple installed targets must not carry image-target evidence")
      ("linux-native", Nothing) ->
        ioError (userError "Linux image target evidence is missing")
      _ ->
        ioError (userError "engine artifact target substrate is unsupported")
    expectedGenerationFingerprint <-
      either
        (ioError . userError)
        pure
        ( engineArtifactGenerationFingerprint
            (manifestSubstrate manifest)
            (manifestDigest manifest)
            (manifestRecipeFingerprint manifest)
            (manifestTargetContractFingerprint manifest)
            (manifestImageTargetEvidence manifest)
        )
    when (contractMode == ExactManifestContract) $
      unless
        (manifestGenerationFingerprint manifest == expectedGenerationFingerprint)
        (ioError (userError "engine artifact generation fingerprint changed"))
    when (manifestSubstrate manifest == "apple-silicon") $ do
      let adapterId = nativeArtifactAdapterId identity
          requireRuntimeDirectories =
            mapM_
              ( requireOwnedDirectoryAt
                  "Apple engine artifact runtime closure"
                  rootDescriptor
              )
          targetRelativePath =
            makeRelative
              actualRoot
              (nativeArtifactTargetExecutable actualRoot target)
          requireTarget label =
            void
              ( requireOwnedExecutableRegularFileAt
                  label
                  rootDescriptor
                  targetRelativePath
              )
      if
        | adapterId
            `elem` [ "ctranslate2-native",
                     "onnx-runtime-native",
                     "mlx-native",
                     "coreml-native"
                   ] -> do
            requireRuntimeDirectories
              [ "python-home",
                "python-frameworks",
                "python-frameworks/Python.framework",
                "native",
                "native/lib",
                "native/libexec",
                "venv",
                "venv/bin"
              ]
            requireTarget "Apple engine artifact runner Python"
            void
              ( requireOwnedPathAt
                  "Apple engine artifact pyvenv configuration"
                  "a regular file"
                  isRegularFile
                  rootDescriptor
                  "venv/pyvenv.cfg"
              )
        | adapterId `elem` ["llama-cpp-cli", "whisper-cpp-cli"] -> do
            requireRuntimeDirectories
              ["native", "native/bin", "native/lib", "native/libexec"]
            requireTarget "Apple engine artifact native CLI"
        | adapterId == "jvm-native" -> do
            requireRuntimeDirectories
              [ "Audiveris.app",
                "Audiveris.app/Contents",
                "Audiveris.app/Contents/MacOS"
              ]
            requireTarget "Apple engine artifact application target"
        | otherwise ->
            ioError
              (userError "Apple engine artifact has no closed runtime closure")

validateExactManifestContract :: EngineArtifactManifest -> IO ()
validateExactManifestContract manifest = do
  validateCurrentRecipeFingerprint manifest
  digestHex <-
    maybe
      ( ioError
          ( userError
              ( "engine artifact digest is not canonical sha256: "
                  <> Text.unpack (manifestDigest manifest)
              )
          )
      )
      pure
      (canonicalSha256Hex (manifestDigest manifest))
  mapM_
    requireObjectKeyComponent
    [ ("substrate", objectKeySubstrate manifest),
      ("architecture", manifestArchitecture manifest),
      ("adapterId", manifestAdapterId manifest)
    ]
  let expectedObjectKey =
        Text.intercalate
          "/"
          [ "engine-artifacts",
            objectKeySubstrate manifest,
            manifestArchitecture manifest,
            manifestAdapterId manifest,
            digestHex <> ".tar.zst"
          ]
  unless (manifestMinioObjectKey manifest == expectedObjectKey) $
    ioError
      ( userError
          ( "engine artifact MinIO object key mismatch: expected "
              <> Text.unpack expectedObjectKey
              <> ", observed "
              <> Text.unpack (manifestMinioObjectKey manifest)
          )
      )
  when
    ( manifestSubstrate manifest == "apple-silicon"
        && null (manifestResolvedProvenance manifest)
    )
    ( ioError
        ( userError
            "exact Apple engine artifact manifest has no resolved provenance"
        )
    )

validateCurrentRecipeFingerprint :: EngineArtifactManifest -> IO ()
validateCurrentRecipeFingerprint manifest = do
  identity <-
    maybe
      ( ioError
          ( userError
              ( "engine artifact adapter has no closed native identity: "
                  <> Text.unpack (manifestAdapterId manifest)
              )
          )
      )
      pure
      (parseNativeArtifactIdentity (manifestAdapterId manifest))
  expectedRecipeFingerprint <-
    either
      (ioError . userError)
      pure
      ( nativeArtifactRecipeFingerprint
          identity
          (manifestSubstrate manifest)
          (manifestArchitecture manifest)
      )
  unless
    (manifestRecipeFingerprint manifest == expectedRecipeFingerprint)
    ( ioError
        ( userError
            ( "engine artifact recipe fingerprint is not current: expected "
                <> Text.unpack expectedRecipeFingerprint
                <> ", observed "
                <> Text.unpack (manifestRecipeFingerprint manifest)
            )
        )
    )

objectKeySubstrate :: EngineArtifactManifest -> Text
objectKeySubstrate manifest =
  case manifestSubstrate manifest of
    "linux-native" -> "linux"
    substrate -> substrate

requireObjectKeyComponent :: (String, Text) -> IO ()
requireObjectKeyComponent (componentName, component) =
  when
    ( Text.null component
        || component `elem` [".", ".."]
        || Text.any (`elem` ['/', '\\', '\0']) component
    )
    ( ioError
        ( userError
            ( "invalid engine artifact object-key "
                <> componentName
                <> " component: "
                <> Text.unpack component
            )
        )
    )

canonicalSha256Hex :: Text -> Maybe Text
canonicalSha256Hex digest = do
  digestHex <- Text.stripPrefix "sha256:" digest
  if Text.length digestHex == 64
    && Text.all (`Text.elem` "0123456789abcdef") digestHex
    then Just digestHex
    else Nothing

data ArtifactResolution a
  = ArtifactResolved a
  | ArtifactUnavailable ![FilePath]
  | ArtifactRejected !FilePath !String
  | ArtifactBusy !FilePath

data ArtifactRuntimeExpectation
  = ArtifactRuntimeExpectation !Text !Text

appleArtifactRuntimeExpectation :: ArtifactRuntimeExpectation
appleArtifactRuntimeExpectation =
  ArtifactRuntimeExpectation "apple-silicon" "arm64"

linuxArtifactRuntimeExpectation :: ArtifactRuntimeExpectation
linuxArtifactRuntimeExpectation =
  ArtifactRuntimeExpectation "linux-native" nativeArchitecture
  where
    nativeArchitecture =
      case SystemInfo.arch of
        "x86_64" -> "amd64"
        "aarch64" -> "arm64"
        other -> Text.pack other

-- | The current closed recipe for one exact identity/lane pair. Every
-- materializer writes this value and every reader independently derives it.
currentArtifactRecipeFingerprint ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  Either String Text
currentArtifactRecipeFingerprint
  identity
  (ArtifactRuntimeExpectation substrate architecture) =
    nativeArtifactRecipeFingerprint identity substrate architecture

-- | Re-derive, helper-side, the generation identity a parent handed down,
-- taking nothing from the parent but the lane and the payload digest the caller
-- has just re-computed from bytes.
--
-- This exists because asserting @generationFingerprint == payloadDigest@ is not
-- a general property of a generation identity: it is the @apple-silicon@ branch
-- of 'engineArtifactGenerationFingerprint'. A @linux-native@ generation
-- additionally binds the current recipe, the closed target contract, and the
-- descriptor-derived image-target evidence, precisely because a Linux metadata
-- root does not contain the image-owned payload it will execute. Its identity is
-- therefore never its own payload digest, and a helper applying the Apple
-- assertion to it can never admit any Linux generation at all.
--
-- Everything the equation needs is independently derivable here, so nothing is
-- taken on trust: the recipe fingerprint and the target contract come from the
-- closed catalog entry for the named lane, and the image-target evidence is
-- re-observed through descriptors against the immutable image. A swapped
-- generation, a drifted recipe, or a changed image therefore fails to reproduce
-- the fingerprint.
rederiveArtifactGenerationFingerprint ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  FilePath ->
  Text ->
  IO (Either String Text)
rederiveArtifactGenerationFingerprint
  identity
  runtimeExpectation@(ArtifactRuntimeExpectation substrate architecture)
  artifactRoot
  payloadDigest =
    case ( nativeArtifactTarget identity substrate architecture,
           currentArtifactRecipeFingerprint identity runtimeExpectation
         ) of
      (Left failure, _) -> pure (Left failure)
      (_, Left failure) -> pure (Left failure)
      (Right target, Right recipeFingerprint) -> do
        -- An Apple installed generation carries no image-target evidence by
        -- construction, and 'engineArtifactGenerationFingerprint' rejects one
        -- that does. Its runtime closure is inside the payload digest already.
        maybeEvidence <-
          if substrate == "linux-native"
            then Just <$> observeNativeArtifactTargetEvidence artifactRoot target
            else pure Nothing
        pure
          ( engineArtifactGenerationFingerprint
              substrate
              payloadDigest
              recipeFingerprint
              (nativeArtifactTargetFingerprint target)
              maybeEvidence
          )

-- | Stable generation identity used by the kernel-managed generation lease.
-- Apple targets and their runtime closure are entirely inside the payload
-- digest. Linux metadata roots deliberately do not copy image-owned native
-- payloads, so their identity additionally binds the current recipe, closed
-- target contract, and complete descriptor-derived target/loader evidence.
engineArtifactGenerationFingerprint ::
  Text ->
  Text ->
  Text ->
  Text ->
  Maybe NativeArtifactTargetEvidence ->
  Either String Text
engineArtifactGenerationFingerprint
  substrate
  payloadDigest
  recipeFingerprint
  targetContractFingerprint
  maybeTargetEvidence = do
    mapM_
      requireCanonicalFingerprint
      [ ("payload digest", payloadDigest),
        ("recipe fingerprint", recipeFingerprint),
        ("target contract fingerprint", targetContractFingerprint)
      ]
    case (substrate, maybeTargetEvidence) of
      ("apple-silicon", Nothing) ->
        Right payloadDigest
      ("linux-native", Just targetEvidence) -> do
        let evidenceFingerprint =
              nativeArtifactTargetEvidenceFingerprint targetEvidence
        requireCanonicalFingerprint
          ("target evidence fingerprint", evidenceFingerprint)
        unless
          ( targetEvidenceContractFingerprint targetEvidence
              == targetContractFingerprint
          )
          (Left "Linux target evidence disagrees with its closed target contract")
        Right
          ( "sha256:"
              <> TextEncoding.decodeUtf8
                ( Base16.encode
                    ( SHA256.hash
                        ( TextEncoding.encodeUtf8
                            ( Text.intercalate
                                "\0"
                                [ "infernix-engine-generation-v1",
                                  payloadDigest,
                                  recipeFingerprint,
                                  targetContractFingerprint,
                                  evidenceFingerprint,
                                  ""
                                ]
                            )
                        )
                    )
                )
          )
      ("apple-silicon", Just _) ->
        Left "Apple installed generation must not carry image-target evidence"
      ("linux-native", Nothing) ->
        Left "Linux generation lacks complete image-target evidence"
      _ ->
        Left "engine artifact generation substrate is unsupported"
    where
      requireCanonicalFingerprint (label, value) =
        unless
          (case canonicalSha256Hex value of Just _ -> True; Nothing -> False)
          (Left ("engine artifact " <> label <> " is not canonical sha256"))

-- | Resolve candidates in declared order. A missing candidate falls through,
-- while the first present but invalid root fails closed instead of allowing a
-- lower-priority root to mask corruption. This runner owns the whole phase
-- sequence — validate, revalidate, launch, reap — under the matching shared
-- materialization lock. The caller supplies only an unprivileged
-- 'ArtifactLauncher' over the closed 'ArtifactLaunchRequest', so it never holds
-- a validated capability, a phase value, or a next-phase continuation.
withFirstValidatedEngineArtifact ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  [FilePath] ->
  ArtifactLauncher ->
  IO (ArtifactResolution ArtifactTerminalOutcome)
withFirstValidatedEngineArtifact identity runtimeExpectation installRoots =
  withFirstValidatedEngineArtifactUnderPreLaunchFixture
    identity
    runtimeExpectation
    installRoots
    noArtifactPreLaunchFixture

-- | The same runner under a fixed, first-order pre-launch fixture. The fixture
-- pins the use-boundary window between minting the ready run and the runner's
-- own revalidation; it carries data only and never an effect or an authority.
withFirstValidatedEngineArtifactUnderPreLaunchFixture ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  [FilePath] ->
  ArtifactPreLaunchFixture ->
  ArtifactLauncher ->
  IO (ArtifactResolution ArtifactTerminalOutcome)
withFirstValidatedEngineArtifactUnderPreLaunchFixture
  identity
  runtimeExpectation
  installRoots
  preLaunchFixture
  launcher =
    resolveCandidates [] installRoots
    where
      resolveCandidates missingRoots [] =
        pure (ArtifactUnavailable (reverse missingRoots))
      resolveCandidates missingRoots (installRoot : remainingRoots) = do
        candidateStatus <- pathStatus installRoot
        case candidateStatus of
          Nothing ->
            resolveCandidates
              (installRoot : missingRoots)
              remainingRoots
          Just _ -> do
            maybeCandidateResolution <-
              withTryEngineArtifactReadLock (takeDirectory installRoot) $ do
                lockedStatus <- pathStatus installRoot
                case lockedStatus of
                  Nothing -> pure CandidateDisappeared
                  Just _ -> do
                    validation <-
                      try @IOException
                        ( mintValidatedEngineArtifact
                            identity
                            runtimeExpectation
                            installRoot
                        )
                    case validation of
                      Left failure ->
                        pure
                          ( CandidateCompleted
                              ( ArtifactRejected
                                  installRoot
                                  (show failure)
                              )
                          )
                      Right validatedArtifact -> do
                        maybeTerminalOutcome <-
                          runArtifactRun
                            ( Capability.reapArtifactRun
                                revalidatedArtifactIsExact
                                preLaunchFixture
                                launcher
                                (Capability.readyArtifactRun validatedArtifact)
                            )
                        pure
                          ( CandidateCompleted
                              ( leasedCandidateResolution
                                  installRoot
                                  maybeTerminalOutcome
                              )
                          )
            case maybeCandidateResolution of
              Nothing -> pure (ArtifactBusy installRoot)
              Just candidateResolution ->
                case candidateResolution of
                  CandidateDisappeared ->
                    resolveCandidates
                      (installRoot : missingRoots)
                      remainingRoots
                  CandidateCompleted resolution -> pure resolution

-- | A refused generation read lease means a writer holds the generation, which
-- is the same answer as a contended engines root: busy, not rejected.
leasedCandidateResolution ::
  FilePath ->
  Maybe ArtifactTerminalOutcome ->
  ArtifactResolution ArtifactTerminalOutcome
leasedCandidateResolution installRoot maybeTerminalOutcome =
  case maybeTerminalOutcome of
    Nothing -> ArtifactBusy installRoot
    Just terminalOutcome -> ArtifactResolved terminalOutcome

data CandidateResolution a
  = CandidateDisappeared
  | CandidateCompleted !(ArtifactResolution a)

-- | 'Nothing' means the exact generation's shared read lease was refused, so
-- the reap transition never reached a launch. The terminal outcome is still
-- forced while the engines-root shared lock is held, which is the lock that
-- keeps the artifact root stable; the generation lease nested inside it is
-- finer-grained and does not change that guarantee.
runArtifactRun ::
  IO (Maybe (ArtifactRun s 'ArtifactReaped)) ->
  IO (Maybe ArtifactTerminalOutcome)
runArtifactRun reapedAction = do
  maybeReaped <- reapedAction
  case maybeReaped of
    Nothing -> pure Nothing
    Just reaped ->
      Just
        <$> evaluate
          (forceArtifactTerminalOutcome (Capability.artifactRunOutcome reaped))

-- | The runner-owned revalidation spent by 'Capability.reapArtifactRun'
-- immediately before the launch request is derived. A caller cannot skip it
-- because it never reaches the transition.
revalidatedArtifactIsExact ::
  ValidatedEngineArtifact s ->
  IO Bool
revalidatedArtifactIsExact validatedArtifact = do
  revalidation <-
    try @IOException (revalidateValidatedEngineArtifact validatedArtifact)
  pure (either (const False) (const True) revalidation)

forceArtifactTerminalOutcome ::
  ArtifactTerminalOutcome ->
  ArtifactTerminalOutcome
forceArtifactTerminalOutcome terminalOutcome =
  case terminalOutcome of
    ArtifactTerminalCompleted ->
      terminalOutcome
    ArtifactTerminalRejected ->
      terminalOutcome
    ArtifactTerminalProcess
      processOutcome
      exitCode
      stdoutOutput
      stderrOutput ->
        forceArtifactProcessOutcome processOutcome `seq`
          exitCode `seq`
            ByteString.length stdoutOutput `seq`
              ByteString.length stderrOutput `seq`
                terminalOutcome

forceArtifactProcessOutcome :: ArtifactProcessOutcome -> ()
forceArtifactProcessOutcome processOutcome =
  case processOutcome of
    ArtifactProcessExited exitCode -> exitCode `seq` ()
    ArtifactProcessExceededCeiling observedBytes -> observedBytes `seq` ()
    ArtifactProcessEnforcementUnavailable reason -> Text.length reason `seq` ()
    ArtifactProcessOutputLimitExceeded outputStream -> outputStream `seq` ()
    ArtifactProcessOutputCaptureFailed outputStream reason ->
      outputStream `seq` Text.length reason `seq` ()

mintValidatedEngineArtifact ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  FilePath ->
  IO (ValidatedEngineArtifact s)
mintValidatedEngineArtifact
  identity
  (ArtifactRuntimeExpectation expectedSubstrate expectedArchitecture)
  installRoot = do
    let expectedAdapterId = nativeArtifactAdapterId identity
    target <-
      either
        (ioError . userError)
        pure
        (nativeArtifactTarget identity expectedSubstrate expectedArchitecture)
    manifest <- validateEngineArtifactRootAt installRoot installRoot
    unless (manifestAdapterId manifest == expectedAdapterId) $
      ioError
        ( userError
            ( "engine artifact adapter mismatch: expected "
                <> Text.unpack expectedAdapterId
                <> ", observed "
                <> Text.unpack (manifestAdapterId manifest)
            )
        )
    unless
      ( manifestSubstrate manifest == expectedSubstrate
          && manifestArchitecture manifest == expectedArchitecture
      )
      ( ioError
          ( userError
              ( "engine artifact runtime mismatch: expected "
                  <> Text.unpack expectedSubstrate
                  <> "/"
                  <> Text.unpack expectedArchitecture
                  <> ", observed "
                  <> Text.unpack (manifestSubstrate manifest)
                  <> "/"
                  <> Text.unpack (manifestArchitecture manifest)
              )
          )
      )
    let manifestPath = engineArtifactManifestPath installRoot
        entrypointPath =
          nativeArtifactTargetExecutable installRoot target
    rootStatus <- requireOwnedDirectory "engine artifact root" installRoot
    manifestStatus <-
      requireOwnedRegularFileStatus
        "engine artifact manifest"
        manifestPath
    entrypointStatus <- getSymbolicLinkStatus entrypointPath
    generationLease <-
      either
        (ioError . userError . ("derive validated artifact generation lease: " <>))
        pure
        ( artifactGenerationLease
            (takeDirectory installRoot)
            identity
            (manifestGenerationFingerprint manifest)
            (manifestDigest manifest)
        )
    -- Requiring the sidecar here, rather than only at acquisition, keeps the
    -- classification of a generation that no writer ever minted the same as
    -- every other validation failure: the caller's 'try' turns it into a
    -- rejection naming this root. It is sound at this point because the
    -- engines-root shared lock is held, and lease retirement runs only under
    -- that root's exclusive writer authority.
    _ <-
      requireOwnedRegularFileStatus
        "engine artifact generation lease sidecar"
        (artifactGenerationLeasePath generationLease)
    pure
      ValidatedEngineArtifact
        { validatedArtifactInstallRoot = installRoot,
          validatedArtifactEntrypoint = entrypointPath,
          validatedArtifactLeadingArguments =
            nativeArtifactTargetLeadingArguments
              installRoot
              expectedAdapterId
              target,
          validatedArtifactManifestFingerprint =
            manifestFingerprint manifest,
          validatedArtifactGenerationLease = generationLease,
          validatedArtifactRootStatus = rootStatus,
          validatedArtifactManifestStatus = manifestStatus,
          validatedArtifactEntrypointStatus = entrypointStatus
        }

manifestFingerprint :: EngineArtifactManifest -> Text
manifestFingerprint manifest =
  "sha256:"
    <> TextEncoding.decodeUtf8
      (Base16.encode (SHA256.hashlazy (renderEngineArtifactManifest manifest)))

-- | Full use-boundary revalidation. The capped-engine kernel calls this
-- immediately before deriving the process specification, while the shared
-- materialization lock is still held. Nested payload tampering is therefore
-- detected even when the root, manifest, and entrypoint inodes are unchanged.
revalidateValidatedEngineArtifact ::
  ValidatedEngineArtifact s ->
  IO ()
revalidateValidatedEngineArtifact
  ( ValidatedEngineArtifact
      installRoot
      entrypoint
      _leadingArguments
      manifestFingerprintValue
      _generationLease
      rootStatus
      manifestStatus
      entrypointStatus
    ) =
    revalidateEngineArtifactEvidence
      installRoot
      entrypoint
      manifestFingerprintValue
      rootStatus
      manifestStatus
      entrypointStatus

revalidateEngineArtifactEvidence ::
  FilePath ->
  FilePath ->
  Text ->
  FileStatus ->
  FileStatus ->
  FileStatus ->
  IO ()
revalidateEngineArtifactEvidence
  installRoot
  entrypoint
  manifestFingerprintValue
  rootStatus
  manifestStatus
  entrypointStatus = do
    manifest <-
      validateEngineArtifactRootAt
        installRoot
        installRoot
    unless
      ( manifestFingerprint manifest
          == manifestFingerprintValue
      )
      ( ioError
          ( userError
              "engine artifact manifest changed after capability validation"
          )
      )
    requireStablePathStatus
      "engine artifact root"
      installRoot
      rootStatus
    requireStablePathStatus
      "engine artifact manifest"
      (engineArtifactManifestPath installRoot)
      manifestStatus
    requireStablePathStatus
      "engine artifact entrypoint"
      entrypoint
      entrypointStatus

-- | Rebuild exact artifact evidence inside a self-executed helper after it
-- has acquired its own shared materialization lease. The expected manifest
-- fingerprint came from the parent's overlapping validated region, so a
-- materializer cannot swap roots between parent validation and helper
-- custody.
validateEngineArtifactHelperLease ::
  NativeArtifactIdentity ->
  ArtifactRuntimeExpectation ->
  FilePath ->
  Text ->
  Text ->
  Text ->
  IO ()
validateEngineArtifactHelperLease
  identity
  (ArtifactRuntimeExpectation expectedSubstrate expectedArchitecture)
  installRoot
  expectedManifestFingerprint
  expectedGenerationFingerprint
  expectedPayloadDigest = do
    manifest <- validateEngineArtifactRootAt installRoot installRoot
    let expectedAdapterId = nativeArtifactAdapterId identity
    unless
      ( manifestAdapterId manifest == expectedAdapterId
          && manifestSubstrate manifest == expectedSubstrate
          && manifestArchitecture manifest == expectedArchitecture
          && manifestFingerprint manifest == expectedManifestFingerprint
          && manifestGenerationFingerprint manifest
            == expectedGenerationFingerprint
          && manifestDigest manifest == expectedPayloadDigest
      )
      ( ioError
          ( userError
              "engine artifact helper lease disagreed with the parent validation"
          )
      )

-- | Rebuild the payload digest for an exact pre-manifest candidate while the
-- supervisor owns the matching generation read lease. The digest intentionally
-- excludes the manifest body, so the same generation identity survives the
-- candidate-to-installed publication transaction.
validateArtifactGenerationPayloadLease ::
  FilePath ->
  Text ->
  IO ()
validateArtifactGenerationPayloadLease artifactRoot expectedPayloadDigest = do
  observedPayloadDigest <- digestEngineArtifactPayload artifactRoot
  unless (observedPayloadDigest == expectedPayloadDigest) $
    ioError
      ( userError
          ( "engine artifact generation payload digest mismatch: expected "
              <> Text.unpack expectedPayloadDigest
              <> ", observed "
              <> Text.unpack observedPayloadDigest
          )
      )

requireNonemptyManifestField :: (String, Text) -> IO ()
requireNonemptyManifestField (fieldName, value) =
  when (Text.null value) $
    ioError
      (userError ("engine artifact manifest field is empty: " <> fieldName))

validateResolvedProvenance :: ResolvedArtifactProvenance -> IO ()
validateResolvedProvenance provenance =
  mapM_
    requireNonemptyManifestField
    [ ("resolvedProvenance.name", resolvedProvenanceName provenance),
      ("resolvedProvenance.version", resolvedProvenanceVersion provenance),
      ("resolvedProvenance.source", resolvedProvenanceSource provenance)
    ]

reconcileEngineArtifactRoot ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  IO ()
reconcileEngineArtifactRoot authority mutator installRoot = mask $ \_ -> do
  validateInstallRootPath installRoot
  let tempRoot = engineArtifactTempRoot installRoot
      previousRoot = engineArtifactPreviousRoot installRoot
  -- The parent is the engines root the authority was minted over, and the
  -- materialization lock created it before this authority existed, so it is
  -- validated against the authority's exact identity rather than created here.
  -- The superseded `createDirectoryIfMissing` was a pathname write above the
  -- very directory whose identity the authority exists to pin.
  requireAuthorityParent authority installRoot
  finalState <- inspectArtifactRoot installRoot installRoot
  previousState <- inspectArtifactRoot installRoot previousRoot
  tempState <- inspectExactArtifactRoot installRoot tempRoot
  case finalState of
    ExactPayloadRoot -> do
      removeOwnedRootIfPresent mutator previousRoot
      removeOwnedRootIfPresent mutator tempRoot
    LegacyDeclarativeRoot ->
      case previousState of
        MissingRoot -> removeOwnedRootIfPresent mutator tempRoot
        _ ->
          ioError
            ( userError
                ( "legacy engine artifact migration root has ambiguous rollback residue: "
                    <> previousRoot
                )
            )
    MissingRoot ->
      case previousState of
        ExactPayloadRoot ->
          restorePreviousArtifactRoot
            mutator
            installRoot
            tempRoot
            previousRoot
            ExactPriorArtifact
        LegacyDeclarativeRoot ->
          restorePreviousArtifactRoot
            mutator
            installRoot
            tempRoot
            previousRoot
            LegacyMigrationPriorArtifact
        MissingRoot ->
          case tempState of
            ExactPayloadRoot -> do
              synchroniseArtifactTree tempRoot
              renameArtifactRoot mutator tempRoot installRoot
              _ <- validateEngineArtifactRootAt installRoot installRoot
              pure ()
            MissingRoot -> pure ()
            InvalidRoot _ -> removeOwnedRootIfPresent mutator tempRoot
            LegacyDeclarativeRoot ->
              ioError
                ( userError
                    "internal error: exact candidate inspection returned a legacy root"
                )
        InvalidRoot failure ->
          ioError
            ( userError
                ( "cannot recover invalid previous engine artifact root "
                    <> previousRoot
                    <> ": "
                    <> failure
                )
            )
    InvalidRoot finalFailure ->
      case previousState of
        ExactPayloadRoot -> do
          removeOwnedRootIfPresent mutator installRoot
          restorePreviousArtifactRoot
            mutator
            installRoot
            tempRoot
            previousRoot
            ExactPriorArtifact
        LegacyDeclarativeRoot -> do
          removeOwnedRootIfPresent mutator installRoot
          restorePreviousArtifactRoot
            mutator
            installRoot
            tempRoot
            previousRoot
            LegacyMigrationPriorArtifact
        _ ->
          ioError
            ( userError
                ( "engine artifact final root is invalid and no complete rollback root exists: "
                    <> finalFailure
                )
            )

data ArtifactRootState
  = MissingRoot
  | ExactPayloadRoot
  | LegacyDeclarativeRoot
  | InvalidRoot !String

data PriorArtifactRoot
  = NoPriorArtifact
  | ExactPriorArtifact
  | LegacyMigrationPriorArtifact
  deriving (Eq)

inspectArtifactRoot ::
  FilePath ->
  FilePath ->
  IO ArtifactRootState
inspectArtifactRoot expectedInstallRoot candidateRoot = do
  status <- pathStatus candidateRoot
  case status of
    Nothing -> pure MissingRoot
    Just observedStatus
      | not (isDirectory observedStatus) ->
          pure (InvalidRoot "path is not an owned directory")
      | otherwise -> do
          exactValidation <-
            try @IOException
              (validateEngineArtifactRootAt expectedInstallRoot candidateRoot)
          case exactValidation of
            Right _ -> pure ExactPayloadRoot
            Left exactFailure -> do
              legacyValidation <-
                try @IOException
                  (validateLegacyArtifactRootAt expectedInstallRoot candidateRoot)
              pure $
                case legacyValidation of
                  Right () -> LegacyDeclarativeRoot
                  Left legacyFailure ->
                    InvalidRoot
                      ( "exact validation failed: "
                          <> show exactFailure
                          <> "; legacy validation failed: "
                          <> show legacyFailure
                      )

inspectExactArtifactRoot ::
  FilePath ->
  FilePath ->
  IO ArtifactRootState
inspectExactArtifactRoot expectedInstallRoot candidateRoot = do
  status <- pathStatus candidateRoot
  case status of
    Nothing -> pure MissingRoot
    Just observedStatus
      | not (isDirectory observedStatus) ->
          pure (InvalidRoot "path is not an owned directory")
      | otherwise -> do
          validation <-
            try @IOException
              (validateEngineArtifactRootAt expectedInstallRoot candidateRoot)
          pure $
            case validation of
              Right _ -> ExactPayloadRoot
              Left failure -> InvalidRoot (show failure)

-- | Require that an install root's containing directory is exactly the engines
-- root this authority was minted over.
--
-- The authority records that directory's device, inode, and mode at acquisition
-- under the materialization lock, so this both pins the parent identity and
-- proves the transaction is operating where its authority applies. Every
-- parent-level effect in the transaction is a sibling operation in this
-- directory, which is why one check covers all of them.
requireAuthorityParent ::
  MaterializationAuthority w ->
  FilePath ->
  IO ()
requireAuthorityParent authority installRoot = do
  let parent = takeDirectory installRoot
      expected = materializationAuthorityRoot authority
  unless
    (normalise parent == normalise expected)
    ( ioError
        ( userError
            ( "engine artifact install root is not a child of its authority root: "
                <> installRoot
            )
        )
    )
  observed <- pathStatus parent
  case observed of
    Nothing ->
      ioError
        ( userError
            ("engine artifact authority root is absent: " <> parent)
        )
    Just status ->
      unless
        ( isDirectory status
            && not (isSymbolicLink status)
            && fromIntegral (deviceID status)
              == materializationAuthorityDeviceId authority
            && fromIntegral (fileID status)
              == materializationAuthorityFileId authority
            && fromIntegral (fileMode status)
              == materializationAuthorityMode authority
        )
        ( ioError
            ( userError
                ("engine artifact authority root identity changed: " <> parent)
            )
        )

installEngineArtifactRoot ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  IO ()
installEngineArtifactRoot authority mutator installRoot tempRoot = do
  runEngineArtifactActivation
    mutator
    authority
    installRoot
    tempRoot
    Nothing
    (const (pure ()))
    (const (pure ()))
    (pure (CommitArtifactActivation, ()))

installEngineArtifactRootWithExpectedDigest ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  Text ->
  IO ()
installEngineArtifactRootWithExpectedDigest
  authority
  mutator
  installRoot
  tempRoot
  expectedDigest = do
    runEngineArtifactActivation
      mutator
      authority
      installRoot
      tempRoot
      (Just expectedDigest)
      (const (pure ()))
      (const (pure ()))
      (pure (CommitArtifactActivation, ()))

-- | The closed set of parent-level effects an engine-artifact transaction
-- performs on its install root's containing directory.
--
-- Both operands are absolute paths under the writer root that mints the
-- interpreter; a rename's two paths must be siblings. The transaction can
-- request nothing else, which is what makes this a language rather than an
-- effect hook.
data ArtifactRootMutation
  = -- | Rename one directory over an absent sibling name.
    RenameArtifactRootSibling !FilePath !FilePath
  | -- | Remove one owned directory tree, succeeding when it is already absent.
    RemoveArtifactRootSibling !FilePath
  deriving (Eq, Show)

-- | The fixed interpreter for 'ArtifactRootMutation'.
--
-- The mutation kernel that can perform these effects through a retained parent
-- descriptor lives in @Infernix.Cluster.Subprocess@, which already imports the
-- public @Infernix.Engines.Artifact@ facade -- so this module cannot reach it
-- without closing an import cycle. The transaction therefore /requests/ its
-- parent-level effects and the provisioning facade, which holds both the writer
-- root and the kernel, interprets them.
--
-- This is not a caller-supplied effect hook. The constructor is exported from
-- this @.Internal@ module only and is never re-exported by the public
-- @Infernix.Engines.Artifact@ facade, so a value can be minted only by
-- package-internal engine code, and the transaction can express only the two
-- effects above.
newtype ArtifactRootMutator w
  = ArtifactRootMutator (ArtifactRootMutation -> IO ())

type role ArtifactRootMutator nominal

-- | Request one parent-level effect through the transaction's interpreter.
runArtifactRootMutation ::
  ArtifactRootMutator w ->
  ArtifactRootMutation ->
  IO ()
runArtifactRootMutation (ArtifactRootMutator interpret) = interpret

-- | Pathname interpreter for the artifact transaction test suite.
--
-- That suite proves the transaction's /ordering/ -- which root moves when, what
-- a rollback restores, which residue a crash reconciliation accepts -- against
-- synthetic roots in a temporary directory, and is deliberately
-- machine-independent: it requires neither a host manifest nor the self-exec
-- mutation kernel. This interpreter therefore performs the two effects by
-- pathname, which is exactly what the transaction did before its effects were
-- separated from their interpretation, so the suite's coverage is unchanged by
-- that separation.
--
-- It is emphatically not the production interpreter and proves nothing about
-- descriptor anchoring; that is the parent-swap tests' job.
artifactRootMutatorForTest :: ArtifactRootMutator w
artifactRootMutatorForTest =
  ArtifactRootMutator
    ( \case
        RenameArtifactRootSibling source destination -> do
          renameDirectory source destination
          synchroniseDirectoryForTest (takeDirectory destination)
        RemoveArtifactRootSibling path -> do
          removeDirectoryRecursive path
          synchroniseDirectoryForTest (takeDirectory path)
    )

-- | The pathname directory fsync the test interpreter uses.
synchroniseDirectoryForTest :: FilePath -> IO ()
synchroniseDirectoryForTest directoryPath =
  mask $ \restore -> do
    descriptor <-
      openFd
        directoryPath
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True,
            directory = True
          }
    finallyPreservingPrimary
      ( do
          observedStatus <- getFdStatus descriptor
          unless (isDirectory observedStatus) $
            ioError
              ( userError
                  ( "engine artifact path changed while synchronising directory: "
                      <> directoryPath
                  )
              )
          restore (fileSynchronise descriptor)
      )
      (closeFd descriptor)

-- | Rename one owned root over its absent sibling.
renameArtifactRoot ::
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  IO ()
renameArtifactRoot mutator source destination =
  runArtifactRootMutation
    mutator
    (RenameArtifactRootSibling source destination)

data ArtifactActivationBoundary
  = PreviousRootMoved
  | CandidateRootMoved
  deriving (Eq, Show)

newtype ArtifactCleanupBoundary
  = BeforeOwnedArtifactRetirement FilePath
  deriving (Eq, Show)

data ArtifactActivationDecision
  = CommitArtifactActivation
  | RollbackArtifactActivation
  deriving (Eq, Show)

-- | A pending artifact transaction.
--
-- The interpreter is retained on the token rather than supplied again at
-- commit or rollback, so a rollback provably uses the same parent-level
-- interpreter the forward transaction used. Handing a different one to the
-- rollback is not representable.
data ArtifactActivation w
  = ArtifactActivation
      !FilePath
      !FilePath
      !FilePath
      !EngineArtifactManifest
      !(Maybe EngineArtifactManifest)
      !(Maybe Text)
      !ArtifactActivationState
      !(ArtifactCleanupBoundary -> IO ())
      !(ArtifactRootMutator w)

type role ArtifactActivation nominal

data ArtifactActivationState
  = IdempotentArtifactActivation
  | MovedArtifactActivation !PriorArtifactRoot

newtype PendingArtifactActivation w
  = PendingArtifactActivation (ArtifactActivation w)

type role PendingArtifactActivation nominal

data CommittedArtifactActivation w
  = CommittedArtifactActivation
      !EngineArtifactManifest
      !(Maybe EngineArtifactManifest)

type role CommittedArtifactActivation nominal

beginEngineArtifactActivationUnderGeneration ::
  MaterializationAuthority w ->
  ArtifactGenerationMutationAuthority w g ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  Text ->
  IO (PendingArtifactActivation w)
beginEngineArtifactActivationUnderGeneration
  authority
  _generationAuthority
  mutator
  installRoot
  tempRoot
  expectedDigest =
    PendingArtifactActivation
      <$> beginEngineArtifactActivationWithObserver
        mutator
        authority
        installRoot
        tempRoot
        (Just expectedDigest)
        (const (pure ()))
        (const (pure ()))

pendingArtifactActivationManifest ::
  PendingArtifactActivation w ->
  EngineArtifactManifest
pendingArtifactActivationManifest
  ( PendingArtifactActivation
      (ArtifactActivation _ _ _ manifest _ _ _ _ _)
    ) =
    manifest

pendingArtifactActivationPriorManifest ::
  PendingArtifactActivation w ->
  Maybe EngineArtifactManifest
pendingArtifactActivationPriorManifest
  ( PendingArtifactActivation
      (ArtifactActivation _ _ _ _ priorManifest _ _ _ _)
    ) =
    priorManifest

commitEngineArtifactActivationUnderGeneration ::
  ArtifactGenerationMutationAuthority w g ->
  PendingArtifactActivation w ->
  IO (CommittedArtifactActivation w)
commitEngineArtifactActivationUnderGeneration
  _generationAuthority
  (PendingArtifactActivation activation) = do
    finishEngineArtifactActivation CommitArtifactActivation activation
    let ArtifactActivation
          installRoot
          tempRoot
          previousRoot
          candidateManifest
          priorManifest
          _
          _
          _
          _ = activation
    committedManifest <-
      validateEngineArtifactRootAt installRoot installRoot
    unless (committedManifest == candidateManifest) $
      ioError
        (userError "committed engine artifact differs from the pending candidate")
    tempStatus <- pathStatus tempRoot
    previousStatus <- pathStatus previousRoot
    case (tempStatus, previousStatus) of
      (Nothing, Nothing) -> pure ()
      _ ->
        ioError
          (userError "committed engine artifact retained candidate or rollback residue")
    pure
      (CommittedArtifactActivation committedManifest priorManifest)

rollbackEngineArtifactActivationUnderGeneration ::
  ArtifactGenerationMutationAuthority w g ->
  PendingArtifactActivation w ->
  IO ()
rollbackEngineArtifactActivationUnderGeneration
  _generationAuthority
  (PendingArtifactActivation activation) =
    finishEngineArtifactActivation RollbackArtifactActivation activation

committedArtifactActivationPriorManifest ::
  CommittedArtifactActivation w ->
  Maybe EngineArtifactManifest
committedArtifactActivationPriorManifest
  (CommittedArtifactActivation _ priorManifest) =
    priorManifest

committedArtifactActivationManifest ::
  CommittedArtifactActivation w ->
  EngineArtifactManifest
committedArtifactActivationManifest
  (CommittedArtifactActivation manifest _) =
    manifest

-- | Keep the pending activation entirely inside this module. The supplied
-- action cannot observe or retain transaction authority; an exception rolls
-- back before it is rethrown, and a returned decision is consumed exactly
-- once before the result can leave this bracket.
runEngineArtifactActivation ::
  ArtifactRootMutator w ->
  MaterializationAuthority w ->
  FilePath ->
  FilePath ->
  Maybe Text ->
  (ArtifactActivationBoundary -> IO ()) ->
  (ArtifactCleanupBoundary -> IO ()) ->
  IO (ArtifactActivationDecision, result) ->
  IO result
runEngineArtifactActivation
  mutator
  authority
  installRoot
  tempRoot
  expectedDigest
  observeBoundary
  observeCleanup
  decide =
    mask $ \restore -> do
      activation <-
        beginEngineArtifactActivationWithObserver
          mutator
          authority
          installRoot
          tempRoot
          expectedDigest
          observeBoundary
          observeCleanup
      decisionResult <- try @SomeException (restore decide)
      case decisionResult of
        Left failure ->
          finallyPreservingPrimary
            (throwIO failure)
            ( finishEngineArtifactActivation
                RollbackArtifactActivation
                activation
            )
        Right (decision, result) -> do
          finishEngineArtifactActivation decision activation
          pure result

-- | Run one first-order validation check while activation is pending. The
-- check cannot observe or retain the private activation token. A false result,
-- synchronous exception, or asynchronous cancellation rolls the candidate
-- back before control leaves this function.
activateEngineArtifactAfterCheck ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  Text ->
  IO (Bool, result) ->
  IO result
activateEngineArtifactAfterCheck
  authority
  mutator
  installRoot
  tempRoot
  expectedDigest
  check =
    runEngineArtifactActivation
      mutator
      authority
      installRoot
      tempRoot
      (Just expectedDigest)
      (const (pure ()))
      (const (pure ()))
      ( do
          (checkPassed, result) <- check
          pure
            ( if checkPassed
                then CommitArtifactActivation
                else RollbackArtifactActivation,
              result
            )
      )

-- | Deterministic activation-boundary hook for the artifact transaction test
-- suite. Production modules are forbidden from importing this raw kernel.
installEngineArtifactRootWithObserverForTest ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  (ArtifactActivationBoundary -> IO ()) ->
  IO ()
installEngineArtifactRootWithObserverForTest
  authority
  mutator
  installRoot
  tempRoot
  observeBoundary = do
    runEngineArtifactActivation
      mutator
      authority
      installRoot
      tempRoot
      Nothing
      observeBoundary
      (const (pure ()))
      (pure (CommitArtifactActivation, ()))

-- | Exercise the pending-activation exception boundary without exporting the
-- transaction token. This hook is admitted only by the artifact transaction
-- test suite through the package-internal module boundary.
installEngineArtifactRootWithPendingActionForTest ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  Text ->
  IO () ->
  IO ()
installEngineArtifactRootWithPendingActionForTest
  authority
  mutator
  installRoot
  tempRoot
  expectedDigest
  pendingAction =
    runEngineArtifactActivation
      mutator
      authority
      installRoot
      tempRoot
      (Just expectedDigest)
      (const (pure ()))
      (const (pure ()))
      ( do
          pendingAction
          pure (CommitArtifactActivation, ())
      )

-- | Deterministic commit-retirement hook for recovery tests.
installEngineArtifactRootWithCleanupObserverForTest ::
  MaterializationAuthority w ->
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  Text ->
  (ArtifactCleanupBoundary -> IO ()) ->
  IO ()
installEngineArtifactRootWithCleanupObserverForTest
  authority
  mutator
  installRoot
  tempRoot
  expectedDigest
  observeCleanup =
    runEngineArtifactActivation
      mutator
      authority
      installRoot
      tempRoot
      (Just expectedDigest)
      (const (pure ()))
      observeCleanup
      (pure (CommitArtifactActivation, ()))

beginEngineArtifactActivationWithObserver ::
  ArtifactRootMutator w ->
  MaterializationAuthority w ->
  FilePath ->
  FilePath ->
  Maybe Text ->
  (ArtifactActivationBoundary -> IO ()) ->
  (ArtifactCleanupBoundary -> IO ()) ->
  IO (ArtifactActivation w)
beginEngineArtifactActivationWithObserver
  mutator
  authority
  installRoot
  tempRoot
  expectedDigest
  observeBoundary
  observeCleanup =
    mask $ \restore -> do
      validateInstallRootPath installRoot
      requireAuthorityParent authority installRoot
      let expectedTempRoot = engineArtifactTempRoot installRoot
          previousRoot = engineArtifactPreviousRoot installRoot
      unless (tempRoot == expectedTempRoot) $
        ioError
          ( userError
              ( "engine artifact candidate must use the owned sibling path "
                  <> expectedTempRoot
              )
          )
      candidateManifest <-
        restore (validateEngineArtifactRootAt installRoot tempRoot)
      mapM_
        ( requireExpectedCandidateDigest
            "before activation"
            candidateManifest
        )
        expectedDigest
      restore (synchroniseArtifactTree tempRoot)
      finalState <- restore (inspectArtifactRoot installRoot installRoot)
      previousState <- restore (inspectArtifactRoot installRoot previousRoot)
      case previousState of
        MissingRoot -> pure ()
        _ ->
          ioError
            ( userError
                ( "engine artifact rollback root exists before activation; reconcile "
                    <> installRoot
                    <> " before constructing its candidate"
                )
            )
      priorManifest <-
        case finalState of
          ExactPayloadRoot ->
            Just
              <$> restore
                (validateEngineArtifactRootAt installRoot installRoot)
          _ -> pure Nothing
      let idempotentExactRerun =
            priorManifest == Just candidateManifest
      if idempotentExactRerun
        then
          pure
            ( ArtifactActivation
                installRoot
                tempRoot
                previousRoot
                candidateManifest
                priorManifest
                expectedDigest
                IdempotentArtifactActivation
                observeCleanup
                mutator
            )
        else do
          priorArtifact <-
            case finalState of
              MissingRoot -> pure NoPriorArtifact
              ExactPayloadRoot -> pure ExactPriorArtifact
              LegacyDeclarativeRoot -> pure LegacyMigrationPriorArtifact
              InvalidRoot failure ->
                ioError
                  ( userError
                      ( "cannot replace invalid engine artifact root without reconciliation: "
                          <> failure
                      )
                  )
          activation <-
            try @SomeException $ do
              when (priorArtifact /= NoPriorArtifact) $ do
                renameArtifactRoot mutator installRoot previousRoot
                restore (observeBoundary PreviousRootMoved)
              renameArtifactRoot mutator tempRoot installRoot
              restore (observeBoundary CandidateRootMoved)
              validateActivatedArtifact
                installRoot
                candidateManifest
                expectedDigest
          case activation of
            Right () ->
              pure
                ( ArtifactActivation
                    installRoot
                    tempRoot
                    previousRoot
                    candidateManifest
                    priorManifest
                    expectedDigest
                    (MovedArtifactActivation priorArtifact)
                    observeCleanup
                    mutator
                )
            Left failure ->
              finallyPreservingPrimary
                (throwIO failure)
                ( rollbackActivation
                    mutator
                    installRoot
                    tempRoot
                    previousRoot
                    priorArtifact
                )

-- | Finish the private pending activation. Commit revalidates the final payload
-- before retiring rollback state; rollback restores the prior exact or
-- migration root and returns the candidate to its owned sibling path.
finishEngineArtifactActivation ::
  ArtifactActivationDecision ->
  ArtifactActivation w ->
  IO ()
finishEngineArtifactActivation
  decision
  ( ArtifactActivation
      installRoot
      tempRoot
      previousRoot
      candidateManifest
      _priorManifest
      expectedDigest
      activationState
      observeCleanup
      mutator
    ) =
    mask $ \restore ->
      case decision of
        RollbackArtifactActivation ->
          case activationState of
            IdempotentArtifactActivation -> pure ()
            MovedArtifactActivation priorArtifact ->
              rollbackActivation
                mutator
                installRoot
                tempRoot
                previousRoot
                priorArtifact
        CommitArtifactActivation -> do
          validation <-
            try @SomeException
              ( restore
                  ( validateActivatedArtifact
                      installRoot
                      candidateManifest
                      expectedDigest
                  )
              )
          case validation of
            Left failure ->
              case activationState of
                IdempotentArtifactActivation ->
                  throwIO failure
                MovedArtifactActivation priorArtifact ->
                  finallyPreservingPrimary
                    (throwIO failure)
                    ( rollbackActivation
                        mutator
                        installRoot
                        tempRoot
                        previousRoot
                        priorArtifact
                    )
            Right () -> do
              case activationState of
                IdempotentArtifactActivation -> do
                  observeCleanup
                    (BeforeOwnedArtifactRetirement tempRoot)
                  removeOwnedRootIfPresent mutator tempRoot
                MovedArtifactActivation _ -> do
                  observeCleanup
                    (BeforeOwnedArtifactRetirement previousRoot)
                  removeOwnedRootIfPresent mutator previousRoot

validateActivatedArtifact ::
  FilePath ->
  EngineArtifactManifest ->
  Maybe Text ->
  IO ()
validateActivatedArtifact
  installRoot
  candidateManifest
  expectedDigest = do
    activatedManifest <-
      validateEngineArtifactRootAt installRoot installRoot
    unless (activatedManifest == candidateManifest) $
      ioError
        ( userError
            "engine artifact candidate identity changed during activation"
        )
    mapM_
      ( requireExpectedCandidateDigest
          "after activation"
          activatedManifest
      )
      expectedDigest

requireExpectedCandidateDigest ::
  String ->
  EngineArtifactManifest ->
  Text ->
  IO ()
requireExpectedCandidateDigest phase manifest expectedDigest =
  unless (manifestDigest manifest == expectedDigest) $
    ioError
      ( userError
          ( "engine artifact candidate digest changed "
              <> phase
              <> ": expected "
              <> Text.unpack expectedDigest
              <> ", observed "
              <> Text.unpack (manifestDigest manifest)
          )
      )

validateInstallRootPath :: FilePath -> IO ()
validateInstallRootPath installRoot =
  let leaf = takeFileName installRoot
   in when
        ( null leaf
            || leaf `elem` [".", ".."]
            || dropTrailingPathSeparator installRoot /= installRoot
        )
        ( ioError
            ( userError
                ( "engine artifact install root must name a directory without "
                    <> "a trailing separator: "
                    <> installRoot
                )
            )
        )

rollbackActivation ::
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  FilePath ->
  PriorArtifactRoot ->
  IO ()
rollbackActivation mutator installRoot tempRoot previousRoot priorArtifact = do
  currentFinal <- ownedDirectoryPresent "engine artifact final root" installRoot
  tempExists <- ownedDirectoryPresent "engine artifact candidate" tempRoot
  previousExists <-
    ownedDirectoryPresent "engine artifact rollback root" previousRoot
  case priorArtifact of
    ExactPriorArtifact -> do
      if previousExists
        then do
          when (currentFinal && tempExists) $
            ioError
              ( userError
                  "engine artifact rollback found both a final root and candidate"
              )
          when currentFinal (renameArtifactRoot mutator installRoot tempRoot)
          renameArtifactRoot mutator previousRoot installRoot
        else
          unless (currentFinal && tempExists) $
            ioError
              ( userError
                  "engine artifact rollback cannot prove that the prior root remained final"
              )
      _ <- validateEngineArtifactRootAt installRoot installRoot
      pure ()
    LegacyMigrationPriorArtifact -> do
      if previousExists
        then do
          when (currentFinal && tempExists) $
            ioError
              ( userError
                  "engine artifact rollback found both a final root and candidate"
              )
          when currentFinal (renameArtifactRoot mutator installRoot tempRoot)
          renameArtifactRoot mutator previousRoot installRoot
        else
          unless (currentFinal && tempExists) $
            ioError
              ( userError
                  "engine artifact rollback cannot prove that the legacy migration root remained final"
              )
      validateLegacyArtifactRootAt installRoot installRoot
    NoPriorArtifact -> do
      when previousExists $
        ioError
          ( userError
              "engine artifact rollback unexpectedly found a prior rollback root"
          )
      when (currentFinal && tempExists) $
        ioError
          ( userError
              "engine artifact rollback found both a final root and candidate"
          )
      unless (currentFinal || tempExists) $
        ioError
          ( userError
              "engine artifact rollback cannot find the uncommitted candidate"
          )
      when currentFinal (renameArtifactRoot mutator installRoot tempRoot)

restorePreviousArtifactRoot ::
  ArtifactRootMutator w ->
  FilePath ->
  FilePath ->
  FilePath ->
  PriorArtifactRoot ->
  IO ()
restorePreviousArtifactRoot
  mutator
  installRoot
  tempRoot
  previousRoot
  priorArtifact = do
    renameArtifactRoot mutator previousRoot installRoot
    case priorArtifact of
      ExactPriorArtifact -> do
        _ <- validateEngineArtifactRootAt installRoot installRoot
        pure ()
      LegacyMigrationPriorArtifact ->
        validateLegacyArtifactRootAt installRoot installRoot
      NoPriorArtifact ->
        ioError
          ( userError
              "internal error: restore requested without a previous artifact"
          )
    removeOwnedRootIfPresent mutator tempRoot

ownedDirectoryPresent :: String -> FilePath -> IO Bool
ownedDirectoryPresent label path = do
  status <- pathStatus path
  case status of
    Nothing -> pure False
    Just observedStatus
      | isDirectory observedStatus && not (isSymbolicLink observedStatus) ->
          pure True
      | otherwise ->
          ioError (userError (label <> " is not an owned directory: " <> path))

requireOwnedDirectory :: String -> FilePath -> IO FileStatus
requireOwnedDirectory label path = do
  status <- getSymbolicLinkStatus path
  when (isSymbolicLink status) $
    ioError (userError (label <> " must not be a symlink: " <> path))
  pure status

requireOwnedRegularFileStatus :: String -> FilePath -> IO FileStatus
requireOwnedRegularFileStatus label path = do
  status <- getSymbolicLinkStatus path
  unless (isRegularFile status && not (isSymbolicLink status)) $
    ioError (userError (label <> " must be a regular file: " <> path))
  pure status

requireOwnedExecutableRegularFileStatus ::
  String ->
  FilePath ->
  IO FileStatus
requireOwnedExecutableRegularFileStatus label path = do
  listedStatus <- requireOwnedRegularFileStatus label path
  withStableRegularFileDescriptor path listedStatus $ \_descriptor openedStatus -> do
    unless (fileMode openedStatus .&. 0o111 /= 0) $
      ioError
        (userError (label <> " must be executable: " <> path))
    pure openedStatus

readDescriptorBounded ::
  String ->
  Int ->
  Fd ->
  IO ByteString.ByteString
readDescriptorBounded label maximumBytes descriptor =
  readChunks 0 []
  where
    readChunks observedBytes chunks = do
      chunk <- readDescriptorChunk descriptor
      let nextObservedBytes = observedBytes + ByteString.length chunk
      when (nextObservedBytes > maximumBytes) $
        ioError
          ( userError
              ( label
                  <> " exceeds the bounded read limit of "
                  <> show maximumBytes
                  <> " bytes"
              )
          )
      if ByteString.null chunk
        then pure (ByteString.concat (reverse chunks))
        else readChunks nextObservedBytes (chunk : chunks)

readDescriptorChunk :: Fd -> IO ByteString.ByteString
readDescriptorChunk =
  readDescriptorChunkSized payloadDigestChunkBytes

readDescriptorChunkSized ::
  ByteCount ->
  Fd ->
  IO ByteString.ByteString
readDescriptorChunkSized requestedBytes descriptor = do
  readResult <-
    try @IOException
      (PosixByteString.fdRead descriptor requestedBytes)
  case readResult of
    Right chunk -> pure chunk
    Left failure
      | isEOFError failure -> pure ByteString.empty
      | otherwise -> ioError failure

withStableRegularFileDescriptor ::
  FilePath ->
  FileStatus ->
  (Fd -> FileStatus -> IO a) ->
  IO a
withStableRegularFileDescriptor path listedStatus action =
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
          openedStatus <- getFdStatus descriptor
          unless
            ( isRegularFile openedStatus
                && stableFileStatusMatches listedStatus openedStatus
            )
            ( ioError
                ( userError
                    ( "engine artifact regular file changed while opening: "
                        <> path
                    )
                )
            )
          result <- restore (action descriptor openedStatus)
          finalDescriptorStatus <- getFdStatus descriptor
          finalPathStatus <- getSymbolicLinkStatus path
          unless
            ( stableFileStatusMatches openedStatus finalDescriptorStatus
                && stableFileStatusMatches finalDescriptorStatus finalPathStatus
                && not (isSymbolicLink finalPathStatus)
            )
            ( ioError
                ( userError
                    ( "engine artifact regular file changed while reading: "
                        <> path
                    )
                )
            )
          pure result
      )
      (closeFd descriptor)

requireStablePathStatus ::
  String ->
  FilePath ->
  FileStatus ->
  IO ()
requireStablePathStatus label path expectedStatus = do
  observedStatus <- getSymbolicLinkStatus path
  unless
    ( stableFileStatusMatches expectedStatus observedStatus
        && not (isSymbolicLink observedStatus)
    )
    ( ioError
        ( userError
            (label <> " changed after exact validation: " <> path)
        )
    )

stableFileStatusMatches :: FileStatus -> FileStatus -> Bool
stableFileStatusMatches firstStatus secondStatus =
  deviceID firstStatus == deviceID secondStatus
    && fileID firstStatus == fileID secondStatus
    && fileMode firstStatus == fileMode secondStatus
    && fileSize firstStatus == fileSize secondStatus
    && modificationTimeHiRes firstStatus == modificationTimeHiRes secondStatus
    && statusChangeTimeHiRes firstStatus == statusChangeTimeHiRes secondStatus

pathStatus :: FilePath -> IO (Maybe FileStatus)
pathStatus path = do
  result <- try @IOException (getSymbolicLinkStatus path)
  case result of
    Right status -> pure (Just status)
    Left failure
      | isDoesNotExistError failure -> pure Nothing
      | otherwise -> ioError failure

-- | Retire one owned artifact root.
--
-- The whole recursive removal is one request on the transaction's interpreter.
-- The superseded form emptied the tree with a local walk and then asked the
-- interpreter to remove the emptied root -- but that walk removed each entry
-- with @removeDirectory (parentPath \<\/\> entryName)@, resolving the entire
-- prefix once per entry. Routing each of those through the kernel individually
-- would cost one subprocess per directory entry, which is not viable for a
-- 35,000-entry artifact. The kernel already performs a bounded recursive
-- descriptor-anchored removal in a single call, opening every level
-- @O_NOFOLLOW@ from its retained parent and identity-checking it, so delegating
-- the whole tree is both cheaper and strictly better anchored.
--
-- The root's kind is still established here before anything is removed, so a
-- non-directory or a symlink at the root is refused rather than removed, and
-- absence is still proven afterwards.
removeOwnedRootIfPresent ::
  ArtifactRootMutator w ->
  FilePath ->
  IO ()
removeOwnedRootIfPresent mutator path = do
  status <- pathStatus path
  case status of
    Nothing -> pure ()
    Just listedStatus
      | isDirectory listedStatus && not (isSymbolicLink listedStatus) -> do
          runArtifactRootMutation
            mutator
            (RemoveArtifactRootSibling path)
          requirePathAbsentAfterRemoval path
      | otherwise ->
          ioError
            ( userError
                ( "refusing to remove non-directory engine artifact path: "
                    <> path
                )
            )

synchroniseArtifactTree :: FilePath -> IO ()
synchroniseArtifactTree root =
  withStableDirectoryDescriptor
    "engine artifact candidate"
    root
    ( \rootDescriptor _ ->
        void
          ( synchroniseArtifactDirectory
              rootDescriptor
              root
              ""
              0
              emptyArtifactTreeTraversal
          )
    )

data ArtifactTreeTraversal = ArtifactTreeTraversal
  { artifactTreeEntryCount :: !Int,
    artifactTreePayloadBytes :: !Integer
  }

emptyArtifactTreeTraversal :: ArtifactTreeTraversal
emptyArtifactTreeTraversal =
  ArtifactTreeTraversal
    { artifactTreeEntryCount = 0,
      artifactTreePayloadBytes = 0
    }

reserveArtifactTreeEntries ::
  Int ->
  Int ->
  ArtifactTreeTraversal ->
  IO ArtifactTreeTraversal
reserveArtifactTreeEntries depth addedEntries traversal = do
  let nextTraversal =
        traversal
          { artifactTreeEntryCount =
              artifactTreeEntryCount traversal + addedEntries
          }
  requireArtifactTreeTraversalBounds depth nextTraversal
  pure nextTraversal

accountArtifactTreeBytes ::
  Int ->
  Integer ->
  ArtifactTreeTraversal ->
  IO ArtifactTreeTraversal
accountArtifactTreeBytes depth addedBytes traversal = do
  let nextTraversal =
        traversal
          { artifactTreePayloadBytes =
              artifactTreePayloadBytes traversal + addedBytes
          }
  requireArtifactTreeTraversalBounds depth nextTraversal
  pure nextTraversal

requireArtifactTreeTraversalBounds ::
  Int ->
  ArtifactTreeTraversal ->
  IO ()
requireArtifactTreeTraversalBounds depth traversal =
  either
    (ioError . userError)
    pure
    ( validateArtifactSnapshotBounds
        (artifactTreeEntryCount traversal)
        (artifactTreePayloadBytes traversal)
        depth
    )

synchroniseArtifactDirectory ::
  Fd ->
  FilePath ->
  FilePath ->
  Int ->
  ArtifactTreeTraversal ->
  IO ArtifactTreeTraversal
synchroniseArtifactDirectory
  directoryDescriptor
  directoryPath
  relativeDirectory
  depth
  traversal = do
    requireArtifactTreeTraversalBounds depth traversal
    initialStatus <- getFdStatus directoryDescriptor
    unless (isDirectory initialStatus) $
      ioError
        ( userError
            ( "engine artifact directory changed type while synchronising: "
                <> displayRelativeArtifactPath relativeDirectory
            )
        )
    entries <-
      readDirectoryEntriesFromDescriptor
        (maximumArtifactSnapshotEntries - artifactTreeEntryCount traversal)
        directoryDescriptor
    reservedTraversal <-
      reserveArtifactTreeEntries depth (length entries) traversal
    finalTraversal <-
      foldM
        ( synchroniseArtifactEntry
            directoryDescriptor
            directoryPath
            relativeDirectory
            depth
        )
        reservedTraversal
        entries
    finalStatus <- getFdStatus directoryDescriptor
    unless (stableFileStatusMatches initialStatus finalStatus) $
      ioError
        ( userError
            ( "engine artifact directory changed while synchronising: "
                <> displayRelativeArtifactPath relativeDirectory
            )
        )
    fileSynchronise directoryDescriptor
    pure finalTraversal

synchroniseArtifactEntry ::
  Fd ->
  FilePath ->
  FilePath ->
  Int ->
  ArtifactTreeTraversal ->
  FilePath ->
  IO ArtifactTreeTraversal
synchroniseArtifactEntry
  parentDescriptor
  parentPath
  relativeDirectory
  depth
  traversal
  entryName = do
    validateEntryName entryName
    let relativePath =
          if null relativeDirectory
            then entryName
            else relativeDirectory </> entryName
    resolution <-
      withStableChildDescriptor
        relativePath
        parentDescriptor
        entryName
        ( \childDescriptor openedStatus ->
            if isRegularFile openedStatus
              then do
                nextTraversal <-
                  accountArtifactTreeBytes
                    depth
                    (toInteger (fileSize openedStatus))
                    traversal
                fileSynchronise childDescriptor
                pure nextTraversal
              else
                if isDirectory openedStatus
                  then
                    synchroniseArtifactDirectory
                      childDescriptor
                      (parentPath </> entryName)
                      relativePath
                      (depth + 1)
                      traversal
                  else
                    ioError
                      ( userError
                          ( "engine artifact payload contains a non-durable file type: "
                              <> relativePath
                          )
                      )
        )
    case resolution of
      ChildDescriptorOpened nextTraversal ->
        pure nextTraversal
      ChildDescriptorSymlink -> do
        (_, target) <-
          readStableArtifactSymlink
            parentDescriptor
            parentPath
            relativePath
            entryName
        validateSymlinkTarget relativePath target
        accountArtifactTreeBytes
          depth
          ( toInteger
              (ByteString.length (TextEncoding.encodeUtf8 (Text.pack target)))
          )
          traversal

requirePathAbsentAfterRemoval :: FilePath -> IO ()
requirePathAbsentAfterRemoval path = do
  remainingStatus <- pathStatus path
  case remainingStatus of
    Nothing -> pure ()
    Just _ ->
      ioError
        (userError ("engine artifact path was replaced during retirement: " <> path))

-- Pre-correction roots used a declarative digest and did not carry resolved
-- provenance. This validator is intentionally disjoint from exact payload
-- validation: callers may use a legacy root only as an explicitly tracked
-- migration predecessor or rollback root.
validateLegacyArtifactRootAt :: FilePath -> FilePath -> IO ()
validateLegacyArtifactRootAt expectedInstallRoot actualRoot = do
  absoluteActualRoot <- makeAbsolute actualRoot
  withStableDirectoryDescriptor
    "legacy engine artifact root"
    absoluteActualRoot
    ( \rootDescriptor _rootStatus -> do
        (_manifestStatus, manifestBytes) <-
          readStableRegularFileAtBounded
            "legacy engine artifact manifest"
            maximumManifestBytes
            rootDescriptor
            "engine-artifact.json"
        manifest <-
          either
            (ioError . userError . ("invalid legacy engine artifact manifest: " <>))
            pure
            (decodeEngineArtifactManifest (LazyByteString.fromStrict manifestBytes))
        validateManifestContract
          LegacyDeclarativeManifestContract
          expectedInstallRoot
          absoluteActualRoot
          rootDescriptor
          manifest
        validateCurrentRecipeFingerprint manifest
        _ <-
          digestEngineArtifactPayloadDescriptor
            (const (pure ()))
            Nothing
            absoluteActualRoot
            rootDescriptor
        unless
          ( manifestLocalInstallRoot manifest == expectedInstallRoot
              && null (manifestResolvedProvenance manifest)
              && manifestDigest manifest == legacyDeclarativeArtifactDigest manifest
          )
          ( ioError
              ( userError
                  "engine artifact root is not a valid pre-correction declarative artifact"
              )
          )
    )

legacyDeclarativeArtifactDigest :: EngineArtifactManifest -> Text
legacyDeclarativeArtifactDigest manifest =
  let digestInput =
        Text.intercalate
          "\n"
          [ manifestAdapterId manifest,
            manifestEngineName manifest,
            manifestArtifactKind manifest,
            manifestSourceRef manifest,
            manifestEngineVersion manifest,
            manifestRuntimeVersion manifest,
            manifestRecipeFingerprint manifest,
            manifestTargetContractFingerprint manifest,
            maybe
              "installed-target"
              targetEvidenceContractFingerprint
              (manifestImageTargetEvidence manifest)
          ]
      digest =
        SHA256.hashlazy
          (LazyByteString.fromStrict (TextEncoding.encodeUtf8 digestInput))
   in "sha256:" <> TextEncoding.decodeUtf8 (Base16.encode digest)
