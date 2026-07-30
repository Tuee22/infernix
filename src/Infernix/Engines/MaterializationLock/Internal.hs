{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}
{-# LANGUAGE TypeApplications #-}

module Infernix.Engines.MaterializationLock.Internal
  ( MaterializationAuthority,
    -- The authority's recorded engines-root identity. Exported so the artifact
    -- transaction can prove its install root's parent is exactly the directory
    -- this authority was acquired over, instead of creating that parent by
    -- pathname. The constructor stays unexported, so an authority still cannot
    -- be forged.
    materializationAuthorityRoot,
    materializationAuthorityDeviceId,
    materializationAuthorityFileId,
    materializationAuthorityMode,
    ArtifactGenerationLease,
    ArtifactGenerationMutationAuthority,
    maximumArtifactGenerationLeaseSidecars,
    maximumArtifactGenerationLeaseDirectoryEntries,
    withEngineMaterializationLock,
    withTryEngineArtifactReadLock,
    artifactGenerationLease,
    artifactGenerationLeaseFields,
    withTryArtifactGenerationMutationLock,
    withTryArtifactGenerationReadLock,
    retireArtifactGenerationLease,
    reconcileObsoleteArtifactGenerationLeases,
    reconcileObsoleteArtifactGenerationLeasesWithPauseForTest,
  )
where

import Control.Concurrent.MVar (MVar, putMVar, takeMVar)
import Control.Exception (IOException, mask, try)
import Control.Monad (guard, unless)
import Data.Bits ((.&.), (.|.))
import Data.Char (isHexDigit, isUpper)
import Data.IORef
  ( IORef,
    newIORef,
    readIORef,
    writeIORef,
  )
import Data.List qualified as List
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Infernix.Cluster.LifecycleLock (withKernelFileLock)
import Infernix.Engines.Artifact.Identity
  ( NativeArtifactIdentity,
    nativeArtifactAdapterId,
    parseNativeArtifactIdentity,
  )
import Infernix.Error
  ( finallyPreservingPrimary,
  )
import System.Directory (createDirectoryIfMissing)
import System.FileLock qualified as FileLock
import System.FilePath (isAbsolute, normalise, takeDirectory, (</>))
import System.IO.Error (isAlreadyExistsError, isDoesNotExistError)
import System.Posix.Directory
  ( closeDirStream,
    readDirStream,
  )
import System.Posix.Directory.Fd (unsafeOpenDirStreamFd)
import System.Posix.Files
  ( FileStatus,
    deviceID,
    fileID,
    fileMode,
    getFdStatus,
    getSymbolicLinkStatus,
    isDirectory,
    isRegularFile,
    isSymbolicLink,
    ownerReadMode,
    ownerWriteMode,
    removeLink,
  )
import System.Posix.IO
  ( OpenFileFlags (cloexec, creat, directory, exclusive, nofollow),
    OpenMode (ReadOnly, WriteOnly),
    closeFd,
    defaultFileFlags,
    dup,
    openFd,
  )
import System.Posix.Types (FileMode)
import System.Posix.Unistd (fileSynchronise)

-- | Nominal evidence that the current continuation owns the exclusive engine
-- materialization lock. The constructor is confined to this module.
data MaterializationAuthority w = MaterializationAuthority
  { materializationAuthorityRoot :: !FilePath,
    materializationAuthorityDeviceId :: !Integer,
    materializationAuthorityFileId :: !Integer,
    materializationAuthorityMode :: !Integer
  }

type role MaterializationAuthority nominal

-- | Stable kernel-lease identity for one exact artifact generation. The lock
-- sidecar is derived from the closed adapter identity and the canonical
-- generation fingerprint, so it remains the same across candidate-to-final
-- rename. The payload digest is retained separately: Linux generation identity
-- also binds image-owned loader evidence that is outside the metadata root.
data ArtifactGenerationLease = ArtifactGenerationLease
  { artifactGenerationLeaseRoot :: !FilePath,
    artifactGenerationLeaseAdapter :: !Text,
    artifactGenerationLeaseFingerprint :: !Text,
    artifactGenerationLeasePayloadDigest :: !Text,
    artifactGenerationLeasePath :: !FilePath
  }
  deriving (Eq, Show)

-- | Scan/reconciliation identity for one sidecar. Payload evidence is not
-- recoverable from a lock filename and is deliberately absent here.
data ArtifactGenerationLockKey
  = ArtifactGenerationLockKey
      !FilePath
      !FilePath

-- | Nominal evidence that the current continuation owns both the global
-- materialization writer lock and this generation's exclusive kernel lease.
-- Both constructors are confined to this module.
data ArtifactGenerationMutationAuthority w g
  = ArtifactGenerationMutationAuthority
      !FilePath
      !Integer
      !Integer
      !Integer
      !(IORef ArtifactGenerationLeaseCustody)

type role ArtifactGenerationMutationAuthority nominal nominal

data ArtifactGenerationLeaseCustody
  = ArtifactGenerationLeaseLive
  | ArtifactGenerationLeaseRetiring
  | ArtifactGenerationLeaseRetired
  deriving (Eq)

data ArtifactGenerationLeaseLeafRequirement
  = AllowMissingArtifactGenerationLeaseLeaf
  | RequireArtifactGenerationLeaseLeaf
  | RequireExactArtifactGenerationLeaseLeaf !FileStatus

maximumArtifactGenerationLeaseSidecars :: Int
maximumArtifactGenerationLeaseSidecars = 128

maximumArtifactGenerationLeaseDirectoryEntries :: Int
maximumArtifactGenerationLeaseDirectoryEntries = 2048

maximumRetainedArtifactGenerationLeases :: Int
maximumRetainedArtifactGenerationLeases = 32

-- | Serialize every writer of an engine-root transaction tree. The pathname
-- may remain after exit, but ownership is exclusively the live kernel lock.
withEngineMaterializationLock ::
  FilePath ->
  (forall w. MaterializationAuthority w -> IO a) ->
  IO a
withEngineMaterializationLock enginesRoot action = do
  unless
    ( isAbsolute enginesRoot
        && normalise enginesRoot == enginesRoot
        && '\NUL' `notElem` enginesRoot
    )
    (ioError (userError "engine materialization root is not absolute and normalized"))
  createDirectoryIfMissing True enginesRoot
  rootBefore <- observeRealDirectory enginesRoot
  lockBefore <-
    ensureRealLockLeaf (enginesRoot </> ".materialization.lock")
  withKernelFileLock
    "engine materialization"
    (enginesRoot </> ".materialization.lock")
    ( do
        rootLocked <- observeRealDirectory enginesRoot
        requireSameDirectory
          "engine materialization root changed before writer acquisition"
          rootBefore
          rootLocked
        lockLocked <-
          observeSameRealLockLeaf
            "engine materialization lock sidecar changed during acquisition"
            lockBefore
            (enginesRoot </> ".materialization.lock")
        finallyPreservingPrimary
          ( action
              MaterializationAuthority
                { materializationAuthorityRoot = enginesRoot,
                  materializationAuthorityDeviceId =
                    fromIntegral (deviceID rootLocked),
                  materializationAuthorityFileId =
                    fromIntegral (fileID rootLocked),
                  materializationAuthorityMode =
                    fromIntegral (fileMode rootLocked)
                }
          )
          ( do
              rootAfter <- observeRealDirectory enginesRoot
              requireSameDirectory
                "engine materialization root changed while writer authority was live"
                rootLocked
                rootAfter
              _ <-
                observeSameRealLockLeaf
                  "engine materialization lock sidecar changed while writer authority was live"
                  lockLocked
                  (enginesRoot </> ".materialization.lock")
              pure ()
          )
    )

-- | Try to keep a validated artifact root stable while a worker executes it.
-- Acquisition is nonblocking so a stopped or long-running materializer cannot
-- turn request resolution into an unbounded wait.
withTryEngineArtifactReadLock :: FilePath -> IO a -> IO (Maybe a)
withTryEngineArtifactReadLock enginesRoot action = do
  unless
    ( isAbsolute enginesRoot
        && normalise enginesRoot == enginesRoot
        && '\NUL' `notElem` enginesRoot
    )
    (ioError (userError "engine materialization read root is not absolute and normalized"))
  mask $ \restore -> do
    rootBefore <- observeRealDirectory enginesRoot
    -- Symmetric with the writer: the sidecar is the lock object itself, so a
    -- root that has never had a writer (an image-baked engine root, for
    -- example) must still be readable. 'ensureRealLockLeaf' creates it only
    -- when absent and validates its exact private mode either way.
    lockBefore <- ensureRealLockLeaf lockPath
    maybeLock <- FileLock.tryLockFile lockPath FileLock.Shared
    case maybeLock of
      Nothing -> do
        rootAfter <- observeRealDirectory enginesRoot
        requireSameDirectory
          "engine materialization read root changed during contention"
          rootBefore
          rootAfter
        _ <-
          observeSameRealLockLeaf
            "engine materialization lock sidecar changed during contention"
            lockBefore
            lockPath
        pure Nothing
      Just lockToken ->
        Just
          <$> finallyPreservingPrimary
            ( do
                rootLocked <- observeRealDirectory enginesRoot
                requireSameDirectory
                  "engine materialization read root changed during acquisition"
                  rootBefore
                  rootLocked
                _ <-
                  observeSameRealLockLeaf
                    "engine materialization lock sidecar changed during read acquisition"
                    lockBefore
                    lockPath
                restore action
            )
            ( finallyPreservingPrimary
                ( do
                    rootAfter <- observeRealDirectory enginesRoot
                    requireSameDirectory
                      "engine materialization read root changed while reader authority was live"
                      rootBefore
                      rootAfter
                    _ <-
                      observeSameRealLockLeaf
                        "engine materialization lock sidecar changed while reader authority was live"
                        lockBefore
                        lockPath
                    pure ()
                )
                (FileLock.unlockFile lockToken)
            )
  where
    lockPath = enginesRoot </> ".materialization.lock"

-- | Validate and derive the stable sidecar for an exact artifact generation.
-- The sidecar sits directly under the engine root, never beneath a renameable
-- candidate or installed artifact directory.
artifactGenerationLease ::
  FilePath ->
  NativeArtifactIdentity ->
  Text ->
  Text ->
  Either String ArtifactGenerationLease
artifactGenerationLease
  enginesRoot
  identity
  generationFingerprint
  payloadDigest = do
    guardEither
      ( isAbsolute enginesRoot
          && normalise enginesRoot == enginesRoot
          && '\NUL' `notElem` enginesRoot
      )
      "artifact generation lease root must be an absolute normalized path"
    guardEither
      (canonicalSha256 generationFingerprint)
      "artifact generation lease fingerprint must be canonical sha256"
    guardEither
      (canonicalSha256 payloadDigest)
      "artifact generation lease payload digest must be canonical sha256"
    let adapterId = nativeArtifactAdapterId identity
        fingerprintHex = Text.drop 7 generationFingerprint
        lockLeaf =
          ".generation-lease-"
            <> Text.unpack adapterId
            <> "-"
            <> Text.unpack fingerprintHex
            <> ".lock"
    pure
      ArtifactGenerationLease
        { artifactGenerationLeaseRoot = enginesRoot,
          artifactGenerationLeaseAdapter = adapterId,
          artifactGenerationLeaseFingerprint = generationFingerprint,
          artifactGenerationLeasePayloadDigest = payloadDigest,
          artifactGenerationLeasePath = enginesRoot </> lockLeaf
        }

-- | Package-internal serialization fields. Deserialization must call
-- 'artifactGenerationLease' again instead of trusting a transmitted path.
artifactGenerationLeaseFields ::
  ArtifactGenerationLease ->
  (FilePath, Text, Text, Text)
artifactGenerationLeaseFields lease =
  ( artifactGenerationLeaseRoot lease,
    artifactGenerationLeaseAdapter lease,
    artifactGenerationLeaseFingerprint lease,
    artifactGenerationLeasePayloadDigest lease
  )

artifactGenerationLockKey ::
  ArtifactGenerationLease ->
  ArtifactGenerationLockKey
artifactGenerationLockKey lease =
  ArtifactGenerationLockKey
    (artifactGenerationLeaseRoot lease)
    (artifactGenerationLeasePath lease)

artifactGenerationLockKeyRoot ::
  ArtifactGenerationLockKey ->
  FilePath
artifactGenerationLockKeyRoot
  (ArtifactGenerationLockKey root _) =
    root

artifactGenerationLockKeyPath ::
  ArtifactGenerationLockKey ->
  FilePath
artifactGenerationLockKeyPath
  (ArtifactGenerationLockKey _ path) =
    path

-- | Try to acquire the generation's exclusive mutation lease while the global
-- writer authority is live. Contention is a typed @Nothing@ rather than an
-- unbounded wait.
withTryArtifactGenerationMutationLock ::
  MaterializationAuthority w ->
  ArtifactGenerationLease ->
  (forall g. ArtifactGenerationMutationAuthority w g -> IO a) ->
  IO (Maybe a)
withTryArtifactGenerationMutationLock authority lease action = do
  requireAuthorityMatchesGenerationLease authority lease
  withTryArtifactGenerationLock
    AllowMissingArtifactGenerationLeaseLeaf
    FileLock.Exclusive
    (artifactGenerationLockKey lease)
    ( \lockStatus custody ->
        action
          ( ArtifactGenerationMutationAuthority
              (artifactGenerationLeasePath lease)
              (fromIntegral (deviceID lockStatus))
              (fromIntegral (fileID lockStatus))
              (fromIntegral (fileMode lockStatus))
              custody
          )
    )

-- | Try to keep one exact generation stable through helper and target reap.
-- The lease is kernel-owned; the pathname may remain after process death but
-- never represents ownership.
withTryArtifactGenerationReadLock ::
  ArtifactGenerationLease ->
  IO a ->
  IO (Maybe a)
withTryArtifactGenerationReadLock lease action =
  withTryArtifactGenerationLock
    RequireArtifactGenerationLeaseLeaf
    FileLock.Shared
    (artifactGenerationLockKey lease)
    (\_status _custody -> action)

withTryArtifactGenerationLock ::
  ArtifactGenerationLeaseLeafRequirement ->
  FileLock.SharedExclusive ->
  ArtifactGenerationLockKey ->
  (FileStatus -> IORef ArtifactGenerationLeaseCustody -> IO a) ->
  IO (Maybe a)
withTryArtifactGenerationLock
  leafRequirement
  lockMode
  generationLockKey
  action = do
    mask $ \restore -> do
      rootBefore <- observeStableGenerationLockRoot generationLockKey
      lockBefore <-
        case leafRequirement of
          AllowMissingArtifactGenerationLeaseLeaf ->
            ensureRealLockLeaf generationLockPath
          RequireArtifactGenerationLeaseLeaf ->
            observeRealLockLeaf generationLockPath
          RequireExactArtifactGenerationLeaseLeaf expected ->
            observeSameRealLockLeaf
              "artifact generation lease sidecar changed after bounded observation"
              expected
              generationLockPath
      maybeLock <-
        FileLock.tryLockFile
          generationLockPath
          lockMode
      case maybeLock of
        Nothing -> do
          rootAfter <- observeStableGenerationLockRoot generationLockKey
          requireSameGenerationLeaseRoot rootBefore rootAfter
          _ <-
            observeSameRealLockLeaf
              "artifact generation lease sidecar changed during contention"
              lockBefore
              generationLockPath
          pure Nothing
        Just lockToken ->
          do
            custody <- newIORef ArtifactGenerationLeaseLive
            Just
              <$> finallyPreservingPrimary
                ( do
                    rootAfter <-
                      observeStableGenerationLockRoot generationLockKey
                    requireSameGenerationLeaseRoot rootBefore rootAfter
                    _ <-
                      observeSameRealLockLeaf
                        "artifact generation lease sidecar changed during acquisition"
                        lockBefore
                        generationLockPath
                    restore (action lockBefore custody)
                )
                ( finallyPreservingPrimary
                    ( validateArtifactGenerationLeaseCustody
                        rootBefore
                        lockBefore
                        generationLockKey
                        custody
                    )
                    (FileLock.unlockFile lockToken)
                )
    where
      generationLockPath =
        artifactGenerationLockKeyPath generationLockKey

-- | Retire an obsolete generation sidecar while its matching exclusive
-- custody and the engine-root writer authority are both live. The custody
-- state lets the enclosing lock finalizer distinguish an intentional,
-- fsynced unlink from an adversarial sidecar replacement.
retireArtifactGenerationLease ::
  MaterializationAuthority w ->
  ArtifactGenerationMutationAuthority w g ->
  ArtifactGenerationLease ->
  IO ()
retireArtifactGenerationLease
  authority
  generationAuthority
  lease = do
    requireAuthorityMatchesGenerationLease authority lease
    retireArtifactGenerationSidecar
      authority
      generationAuthority
      (artifactGenerationLockKey lease)

retireArtifactGenerationSidecar ::
  MaterializationAuthority w ->
  ArtifactGenerationMutationAuthority w g ->
  ArtifactGenerationLockKey ->
  IO ()
retireArtifactGenerationSidecar
  authority
  ( ArtifactGenerationMutationAuthority
      authorityPath
      authorityDevice
      authorityFile
      authorityMode
      custody
    )
  generationLockKey = mask $ \_ -> do
    requireAuthorityMatchesGenerationLockKey authority generationLockKey
    listedStatus <-
      observeRealLockLeaf generationLockPath
    custodyState <- readIORef custody
    unless
      ( custodyState == ArtifactGenerationLeaseLive
          && authorityPath == generationLockPath
          && authorityDevice == fromIntegral (deviceID listedStatus)
          && authorityFile == fromIntegral (fileID listedStatus)
          && authorityMode == fromIntegral (fileMode listedStatus)
      )
      (ioError (userError "artifact generation retirement authority does not match its sidecar"))
    writeIORef custody ArtifactGenerationLeaseRetiring
    removeLink generationLockPath
    synchroniseLockDirectory
      (artifactGenerationLockKeyRoot generationLockKey)
    missing <- try @IOException (observeRealLockLeaf generationLockPath)
    case missing of
      Left failure
        | isDoesNotExistError failure ->
            writeIORef custody ArtifactGenerationLeaseRetired
        | otherwise -> ioError failure
      Right _ ->
        ioError (userError "retired artifact generation sidecar is still present")
    where
      generationLockPath =
        artifactGenerationLockKeyPath generationLockKey

data ObservedArtifactGenerationSidecar
  = ObservedArtifactGenerationSidecar
      !ArtifactGenerationLockKey
      !FileStatus

-- | Bounded recovery for generation sidecars left by failed or previously
-- contended activations. Retained leases reserve their paths even when a
-- proposed generation has not created its sidecar yet. Every other leaf is
-- removed only after a nonblocking exclusive kernel lock and an exact
-- device/inode/mode recheck.
reconcileObsoleteArtifactGenerationLeases ::
  MaterializationAuthority w ->
  [ArtifactGenerationLease] ->
  IO ()
reconcileObsoleteArtifactGenerationLeases authority retainedLeases =
  reconcileObsoleteArtifactGenerationLeasesInternal
    authority
    retainedLeases
    Nothing

-- | Deterministic inode-replacement fixture. The fixed pause occurs after all
-- bounded observations and before the first lock attempt; no caller-supplied
-- effect executes while authority is live.
reconcileObsoleteArtifactGenerationLeasesWithPauseForTest ::
  MaterializationAuthority w ->
  [ArtifactGenerationLease] ->
  MVar () ->
  MVar () ->
  IO ()
reconcileObsoleteArtifactGenerationLeasesWithPauseForTest
  authority
  retainedLeases
  observed
  resume =
    reconcileObsoleteArtifactGenerationLeasesInternal
      authority
      retainedLeases
      (Just (observed, resume))

reconcileObsoleteArtifactGenerationLeasesInternal ::
  MaterializationAuthority w ->
  [ArtifactGenerationLease] ->
  Maybe (MVar (), MVar ()) ->
  IO ()
reconcileObsoleteArtifactGenerationLeasesInternal
  authority
  retainedLeases
  maybePause = do
    validateRetainedArtifactGenerationLeases authority retainedLeases
    observedSidecars <-
      observeBoundedArtifactGenerationSidecars authority
    mapM_
      ( \(observed, resume) -> do
          putMVar observed ()
          takeMVar resume
      )
      maybePause
    retirementResults <-
      mapM
        (retireObservedArtifactGenerationSidecar authority retainedPaths)
        observedSidecars
    let observedPaths =
          map
            observedArtifactGenerationSidecarPath
            observedSidecars
        remainingObserved =
          length
            [ ()
            | retired <- retirementResults,
              not retired
            ]
        reservedMissing =
          length
            [ ()
            | retainedPath <- retainedPaths,
              retainedPath `notElem` observedPaths
            ]
        finalSidecarCount =
          remainingObserved + reservedMissing
    unless
      (finalSidecarCount <= maximumArtifactGenerationLeaseSidecars)
      ( ioError
          ( userError
              "artifact generation sidecar retention exceeds its fixed bound"
          )
      )
    where
      retainedPaths =
        map artifactGenerationLeasePath retainedLeases

validateRetainedArtifactGenerationLeases ::
  MaterializationAuthority w ->
  [ArtifactGenerationLease] ->
  IO ()
validateRetainedArtifactGenerationLeases authority retainedLeases = do
  unless
    ( length retainedLeases <= maximumRetainedArtifactGenerationLeases
        && length retainedPaths == length (List.nub retainedPaths)
    )
    (ioError (userError "retained artifact generation lease set is invalid"))
  mapM_
    (requireAuthorityMatchesGenerationLease authority)
    retainedLeases
  where
    retainedPaths =
      map artifactGenerationLeasePath retainedLeases

retireObservedArtifactGenerationSidecar ::
  MaterializationAuthority w ->
  [FilePath] ->
  ObservedArtifactGenerationSidecar ->
  IO Bool
retireObservedArtifactGenerationSidecar
  authority
  retainedPaths
  (ObservedArtifactGenerationSidecar generationLockKey observedStatus)
    | generationLockPath `elem` retainedPaths =
        pure False
    | otherwise = do
        retired <-
          withTryArtifactGenerationLock
            (RequireExactArtifactGenerationLeaseLeaf observedStatus)
            FileLock.Exclusive
            generationLockKey
            ( \lockStatus custody ->
                retireArtifactGenerationSidecar
                  authority
                  ( ArtifactGenerationMutationAuthority
                      generationLockPath
                      (fromIntegral (deviceID lockStatus))
                      (fromIntegral (fileID lockStatus))
                      (fromIntegral (fileMode lockStatus))
                      custody
                  )
                  generationLockKey
            )
        pure (isJust retired)
    where
      generationLockPath =
        artifactGenerationLockKeyPath generationLockKey

observeBoundedArtifactGenerationSidecars ::
  MaterializationAuthority w ->
  IO [ObservedArtifactGenerationSidecar]
observeBoundedArtifactGenerationSidecars authority =
  mask $ \restore -> do
    descriptor <-
      openFd
        (materializationAuthorityRoot authority)
        ReadOnly
        defaultFileFlags
          { nofollow = True,
            cloexec = True,
            directory = True
          }
    finallyPreservingPrimary
      ( do
          rootBefore <- getFdStatus descriptor
          requireAuthorityMatchesRootStatus authority rootBefore
          duplicateDescriptor <- dup descriptor
          streamResult <-
            try @IOException
              (unsafeOpenDirStreamFd duplicateDescriptor)
          stream <-
            case streamResult of
              Left failure -> do
                closeFd duplicateDescriptor
                ioError failure
              Right opened -> pure opened
          observed <-
            finallyPreservingPrimary
              (restore (readObservedLeases stream 0 0 []))
              (closeDirStream stream)
          rootAfter <- getFdStatus descriptor
          requireSameDirectory
            "artifact generation reconciliation root descriptor changed"
            rootBefore
            rootAfter
          listedRoot <-
            observeRealDirectory
              (materializationAuthorityRoot authority)
          requireSameDirectory
            "artifact generation reconciliation root path changed"
            rootAfter
            listedRoot
          pure (List.sortOn observedLeasePath observed)
      )
      (closeFd descriptor)
  where
    readObservedLeases stream entryCount sidecarCount observed = do
      entry <- readDirStream stream
      if null entry
        then pure observed
        else
          if entry == "." || entry == ".."
            then readObservedLeases stream entryCount sidecarCount observed
            else do
              let nextEntryCount = entryCount + 1
              unless
                ( nextEntryCount
                    <= maximumArtifactGenerationLeaseDirectoryEntries
                )
                ( ioError
                    ( userError
                        "engine materialization root exceeds its fixed directory-entry bound"
                    )
                )
              if artifactGenerationLeaseLeafPrefix `List.isPrefixOf` entry
                then do
                  let nextSidecarCount = sidecarCount + 1
                  unless
                    ( nextSidecarCount
                        <= maximumArtifactGenerationLeaseSidecars
                    )
                    ( ioError
                        ( userError
                            "artifact generation sidecar count exceeds its fixed bound"
                        )
                    )
                  generationLockKey <-
                    either
                      (ioError . userError)
                      pure
                      ( artifactGenerationLockKeyFromLeaf
                          (materializationAuthorityRoot authority)
                          entry
                      )
                  status <-
                    observeRealLockLeaf
                      (artifactGenerationLockKeyPath generationLockKey)
                  readObservedLeases
                    stream
                    nextEntryCount
                    nextSidecarCount
                    ( ObservedArtifactGenerationSidecar
                        generationLockKey
                        status
                        : observed
                    )
                else
                  readObservedLeases
                    stream
                    nextEntryCount
                    sidecarCount
                    observed

    observedLeasePath =
      observedArtifactGenerationSidecarPath

observedArtifactGenerationSidecarPath ::
  ObservedArtifactGenerationSidecar ->
  FilePath
observedArtifactGenerationSidecarPath
  (ObservedArtifactGenerationSidecar generationLockKey _) =
    artifactGenerationLockKeyPath generationLockKey

artifactGenerationLeaseLeafPrefix :: String
artifactGenerationLeaseLeafPrefix = ".generation-lease-"

artifactGenerationLockKeyFromLeaf ::
  FilePath ->
  FilePath ->
  Either String ArtifactGenerationLockKey
artifactGenerationLockKeyFromLeaf enginesRoot leaf = do
  body <-
    maybe
      (Left "artifact generation sidecar has an invalid prefix")
      Right
      ( Text.stripPrefix
          (Text.pack artifactGenerationLeaseLeafPrefix)
          (Text.pack leaf)
      )
  withoutSuffix <-
    maybe
      (Left "artifact generation sidecar has an invalid suffix")
      Right
      (Text.stripSuffix (Text.pack ".lock") body)
  let fingerprintLength = 64
      separatorOffset =
        Text.length withoutSuffix - fingerprintLength - 1
  guardEither
    (separatorOffset > 0)
    "artifact generation sidecar has an invalid identity"
  let (adapterSlug, separatorAndFingerprint) =
        Text.splitAt separatorOffset withoutSuffix
  fingerprintHex <-
    case Text.uncons separatorAndFingerprint of
      Just ('-', value) -> Right value
      _ -> Left "artifact generation sidecar has an invalid fingerprint separator"
  guardEither
    ( Text.length fingerprintHex == fingerprintLength
        && Text.all canonicalLowerHexDigit fingerprintHex
    )
    "artifact generation sidecar has a non-canonical fingerprint"
  _identity <-
    maybe
      (Left "artifact generation sidecar has an unknown adapter identity")
      Right
      (parseNativeArtifactIdentity adapterSlug)
  let expectedLeaf =
        artifactGenerationLeaseLeafPrefix
          <> Text.unpack adapterSlug
          <> "-"
          <> Text.unpack fingerprintHex
          <> ".lock"
  guardEither
    (expectedLeaf == leaf)
    "artifact generation sidecar does not round-trip through the closed lease identity"
  pure
    ( ArtifactGenerationLockKey
        enginesRoot
        (enginesRoot </> leaf)
    )

requireAuthorityMatchesRootStatus ::
  MaterializationAuthority w ->
  FileStatus ->
  IO ()
requireAuthorityMatchesRootStatus authority status =
  unless
    ( materializationAuthorityDeviceId authority
        == fromIntegral (deviceID status)
        && materializationAuthorityFileId authority
          == fromIntegral (fileID status)
        && materializationAuthorityMode authority
          == fromIntegral (fileMode status)
    )
    (ioError (userError "materialization authority root identity changed"))

validateArtifactGenerationLeaseCustody ::
  FileStatus ->
  FileStatus ->
  ArtifactGenerationLockKey ->
  IORef ArtifactGenerationLeaseCustody ->
  IO ()
validateArtifactGenerationLeaseCustody
  rootBefore
  lockBefore
  generationLockKey
  custody = do
    rootAfter <-
      observeStableGenerationLockRoot generationLockKey
    requireSameGenerationLeaseRoot rootBefore rootAfter
    custodyState <- readIORef custody
    case custodyState of
      ArtifactGenerationLeaseLive -> do
        _ <-
          observeSameRealLockLeaf
            "artifact generation lease sidecar changed while custody was live"
            lockBefore
            generationLockPath
        pure ()
      ArtifactGenerationLeaseRetiring ->
        requireSameOrAbsentGenerationLeaseSidecar
          lockBefore
          generationLockKey
      ArtifactGenerationLeaseRetired -> do
        observed <-
          try @IOException
            (observeRealLockLeaf generationLockPath)
        case observed of
          Left failure
            | isDoesNotExistError failure -> pure ()
            | otherwise -> ioError failure
          Right _ ->
            ioError
              ( userError
                  "retired artifact generation sidecar was recreated before writer release"
              )
    where
      generationLockPath =
        artifactGenerationLockKeyPath generationLockKey

requireSameOrAbsentGenerationLeaseSidecar ::
  FileStatus ->
  ArtifactGenerationLockKey ->
  IO ()
requireSameOrAbsentGenerationLeaseSidecar
  expected
  generationLockKey = do
    observed <-
      try @IOException
        ( observeSameRealLockLeaf
            "artifact generation lease sidecar changed during retirement"
            expected
            (artifactGenerationLockKeyPath generationLockKey)
        )
    case observed of
      Right _ -> pure ()
      Left failure
        | isDoesNotExistError failure -> pure ()
        | otherwise -> ioError failure

observeStableGenerationLockRoot ::
  ArtifactGenerationLockKey ->
  IO FileStatus
observeStableGenerationLockRoot generationLockKey =
  observeRealDirectory
    (artifactGenerationLockKeyRoot generationLockKey)

requireSameGenerationLeaseRoot ::
  FileStatus ->
  FileStatus ->
  IO ()
requireSameGenerationLeaseRoot =
  requireSameDirectory
    "artifact generation lease root changed during acquisition"

requireAuthorityMatchesGenerationLease ::
  MaterializationAuthority w ->
  ArtifactGenerationLease ->
  IO ()
requireAuthorityMatchesGenerationLease authority lease = do
  requireAuthorityMatchesGenerationLockKey
    authority
    (artifactGenerationLockKey lease)

requireAuthorityMatchesGenerationLockKey ::
  MaterializationAuthority w ->
  ArtifactGenerationLockKey ->
  IO ()
requireAuthorityMatchesGenerationLockKey
  authority
  generationLockKey = do
    observed <-
      observeStableGenerationLockRoot generationLockKey
    if materializationAuthorityRoot authority
      == artifactGenerationLockKeyRoot generationLockKey
      && materializationAuthorityDeviceId authority
        == fromIntegral (deviceID observed)
      && materializationAuthorityFileId authority
        == fromIntegral (fileID observed)
      && materializationAuthorityMode authority
        == fromIntegral (fileMode observed)
      then pure ()
      else
        ioError
          ( userError
              "artifact generation lease is outside the live materialization authority root"
          )

observeRealDirectory :: FilePath -> IO FileStatus
observeRealDirectory directoryPath = do
  status <- getSymbolicLinkStatus directoryPath
  if isDirectory status && not (isSymbolicLink status)
    then pure status
    else
      ioError (userError "materialization lock root is not a real directory")

requireSameDirectory ::
  String ->
  FileStatus ->
  FileStatus ->
  IO ()
requireSameDirectory failure expected observed =
  if deviceID expected == deviceID observed
    && fileID expected == fileID observed
    && fileMode expected == fileMode observed
    then pure ()
    else ioError (userError failure)

ensureRealLockLeaf :: FilePath -> IO FileStatus
ensureRealLockLeaf lockPath = mask $ \_ -> do
  existing <- try @IOException (observeRealLockLeaf lockPath)
  case existing of
    Right status -> pure status
    Left failure
      | isDoesNotExistError failure -> do
          created <-
            try @IOException
              ( createRealLockLeaf lockPath
                  >> observeRealLockLeaf lockPath
              )
          case created of
            Right status -> pure status
            Left createFailure
              | isAlreadyExistsError createFailure ->
                  observeRealLockLeaf lockPath
              | otherwise -> ioError createFailure
      | otherwise -> ioError failure

createRealLockLeaf :: FilePath -> IO ()
createRealLockLeaf lockPath = do
  descriptor <-
    openFd
      lockPath
      WriteOnly
      defaultFileFlags
        { exclusive = True,
          nofollow = True,
          creat = Just privateLockFileMode,
          cloexec = True
        }
  finallyPreservingPrimary
    (fileSynchronise descriptor)
    (closeFd descriptor)
  synchroniseLockDirectory (takeDirectory lockPath)

synchroniseLockDirectory :: FilePath -> IO ()
synchroniseLockDirectory directoryPath = do
  descriptor <-
    openFd
      directoryPath
      ReadOnly
      defaultFileFlags
        { directory = True,
          nofollow = True,
          cloexec = True
        }
  finallyPreservingPrimary
    (fileSynchronise descriptor)
    (closeFd descriptor)

observeRealLockLeaf :: FilePath -> IO FileStatus
observeRealLockLeaf lockPath = do
  status <- getSymbolicLinkStatus lockPath
  unless
    ( isRegularFile status
        && not (isSymbolicLink status)
        && fileMode status .&. 0o777 == privateLockFileMode
    )
    (ioError (userError "materialization lock sidecar is not a real regular file"))
  pure status

observeSameRealLockLeaf ::
  String ->
  FileStatus ->
  FilePath ->
  IO FileStatus
observeSameRealLockLeaf failure expected lockPath = do
  observed <- observeRealLockLeaf lockPath
  unless
    ( deviceID expected == deviceID observed
        && fileID expected == fileID observed
        && fileMode expected == fileMode observed
    )
    (ioError (userError failure))
  pure observed

privateLockFileMode :: FileMode
privateLockFileMode = ownerReadMode .|. ownerWriteMode

canonicalSha256 :: Text -> Bool
canonicalSha256 value =
  Text.length value == 71
    && Text.take 7 value == Text.pack "sha256:"
    && Text.all canonicalLowerHexDigit (Text.drop 7 value)

canonicalLowerHexDigit :: Char -> Bool
canonicalLowerHexDigit character =
  isHexDigit character && not (isUpper character)

guardEither :: Bool -> String -> Either String ()
guardEither condition failure =
  maybe (Left failure) Right (guard condition)
