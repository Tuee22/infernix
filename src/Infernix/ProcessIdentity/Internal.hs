{-# LANGUAGE CPP #-}

module Infernix.ProcessIdentity.Internal
  ( ProcessBirthIdentity (..),
    PublicationTestPoint (..),
    RegisteredProcessIdentity,
    registerOwnedChildProcessIdentity,
    registeredProcessIdentity,
    releaseRegisteredProcessIdentity,
    dropInheritedProcessIdentity,
    maximumRegistryBasenameLengthForTest,
    maximumRegistryEntriesForTest,
    observeProcessIdentityForTest,
    parseProcessBirthIdentity,
    prepareProcessIdentityRegistryForTest,
    publishProcessIdentityCandidateForTest,
    publishProcessIdentityCandidateWithHookForTest,
    readProcessBirthIdentity,
    reconcileProcessIdentityRegistryForTest,
    registeredProcessIdentityForTest,
    registerCurrentProcessIdentity,
    registerProcessIdentityForTest,
    releaseProcessIdentityForTest,
    renderPendingRegistryEntryForTest,
    renderProcessBirthIdentity,
    renderRegistryEntryForTest,
    withCurrentProcessIdentityRegistryLockForTest,
  )
where

import Data.Char (isAlphaNum, isAscii, isDigit)
import Data.Word (Word64)

#if defined(darwin_HOST_OS)
import Control.Exception
  ( IOException,
    bracket,
    finally,
    mask_,
    onException,
    try,
  )
import Control.Monad (foldM, unless, when)
import Data.Bits ((.&.), shiftL, (.|.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.IORef
  ( IORef,
    atomicModifyIORef',
    atomicWriteIORef,
    newIORef,
    readIORef,
  )
import Data.List qualified as List
import Data.Text qualified as Text
import Data.Text.Encoding qualified as TextEncoding
import System.Directory (removeFile)
import System.Entropy (getEntropy)
import System.FileLock
  ( FileLock,
    SharedExclusive (Exclusive),
    lockFile,
    tryLockFile,
    unlockFile,
  )
import System.FilePath ((</>))
import System.IO.Error
  ( isAlreadyExistsError,
    isDoesNotExistError,
  )
import System.IO.Unsafe (unsafePerformIO)
import System.Posix.Directory qualified as PosixDirectory
import System.Posix.Files
  ( FileStatus,
    createLink,
    deviceID,
    fileID,
    fileMode,
    fileOwner,
    getSymbolicLinkStatus,
    groupModes,
    isDirectory,
    isRegularFile,
    otherModes,
    ownerModes,
    ownerReadMode,
    ownerWriteMode,
  )
import System.Posix.IO
  ( OpenFileFlags
      ( cloexec,
        creat,
        exclusive,
        nofollow
      ),
    OpenMode (ReadOnly, WriteOnly),
    closeFd,
    defaultFileFlags,
    openFd,
  )
import System.Posix.Process (getProcessID)
import System.Posix.Types (FileMode)
import System.Posix.Unistd (fileSynchronise)
import System.Posix.User (getEffectiveUserID)
import System.Timeout (timeout)
#elif defined(linux_HOST_OS)
import Control.Exception (IOException, try)
import Data.ByteString (ByteString)
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isSpace)
import Data.List qualified as List
import System.Posix.Process (getProcessID)
import Text.Read (readMaybe)
#endif

data PublicationTestPoint
  = PendingInodeLocked
  | FinalLinkInstalled
  deriving (Eq, Show)

#if !defined(darwin_HOST_OS)

data RegisteredProcessIdentity
  = KernelRegisteredProcessIdentity !Integer !ProcessBirthIdentity

prepareProcessIdentityRegistryForTest :: FilePath -> IO ()
prepareProcessIdentityRegistryForTest _ =
  unavailableRegistryTestSeam

registerProcessIdentityForTest ::
  FilePath ->
  Integer ->
  IO RegisteredProcessIdentity
registerProcessIdentityForTest _ _ =
  unavailableRegistryTestSeam

publishProcessIdentityCandidateForTest ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  String ->
  IO (Maybe RegisteredProcessIdentity)
publishProcessIdentityCandidateForTest _ _ _ _ =
  unavailableRegistryTestSeam

publishProcessIdentityCandidateWithHookForTest ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  String ->
  (PublicationTestPoint -> IO ()) ->
  IO (Maybe RegisteredProcessIdentity)
publishProcessIdentityCandidateWithHookForTest _ _ _ _ _ =
  unavailableRegistryTestSeam

releaseProcessIdentityForTest :: RegisteredProcessIdentity -> IO ()
releaseProcessIdentityForTest =
  releaseRegisteredProcessIdentity

registeredProcessIdentityForTest ::
  RegisteredProcessIdentity ->
  ProcessBirthIdentity
registeredProcessIdentityForTest
  (KernelRegisteredProcessIdentity _ identity) =
    identity

registerOwnedChildProcessIdentity ::
  Integer ->
  IO RegisteredProcessIdentity
registerOwnedChildProcessIdentity processId = do
  maybeIdentity <- readProcessBirthIdentity processId
  case maybeIdentity of
    Nothing ->
      ioError
        (userError "owned child has no observable kernel birth identity")
    Just identity ->
      pure (KernelRegisteredProcessIdentity processId identity)

registeredProcessIdentity ::
  RegisteredProcessIdentity ->
  (Integer, ProcessBirthIdentity)
registeredProcessIdentity
  (KernelRegisteredProcessIdentity processId identity) =
    (processId, identity)

releaseRegisteredProcessIdentity ::
  RegisteredProcessIdentity ->
  IO ()
releaseRegisteredProcessIdentity _ =
  pure ()

observeProcessIdentityForTest ::
  FilePath ->
  Integer ->
  IO (Maybe ProcessBirthIdentity)
observeProcessIdentityForTest _ _ =
  unavailableRegistryTestSeam

reconcileProcessIdentityRegistryForTest ::
  FilePath ->
  IO [(Integer, ProcessBirthIdentity)]
reconcileProcessIdentityRegistryForTest _ =
  unavailableRegistryTestSeam

renderRegistryEntryForTest ::
  Integer ->
  ProcessBirthIdentity ->
  FilePath
renderRegistryEntryForTest processId identity =
  "process-v1."
    <> show processId
    <> "."
    <> processBirthBootIdentity identity
    <> "-"
    <> show (processBirthStartTime identity)
    <> ".lock"

renderPendingRegistryEntryForTest :: String -> FilePath
renderPendingRegistryEntryForTest nonce =
  ".pending-v1." <> nonce <> ".lock"

maximumRegistryEntriesForTest :: Int
maximumRegistryEntriesForTest = 4096

maximumRegistryBasenameLengthForTest :: Int
maximumRegistryBasenameLengthForTest = 160

unavailableRegistryTestSeam :: IO a
unavailableRegistryTestSeam =
  ioError
    (userError "the isolated process-identity registry is Darwin-only")

withCurrentProcessIdentityRegistryLockForTest :: IO a -> IO a
withCurrentProcessIdentityRegistryLockForTest _ =
  unavailableRegistryTestSeam

#endif

-- | A PID is reusable, so it is not an identity by itself. Linux pairs its
-- kernel process start instant with the current boot identity. Darwin pairs the
-- PID with an entropy-backed token whose exact registry inode remains locked
-- for the lifetime of the registered process.
data ProcessBirthIdentity = ProcessBirthIdentity
  { processBirthBootIdentity :: String,
    processBirthStartTime :: Word64
  }
  deriving (Eq, Show)

renderProcessBirthIdentity :: ProcessBirthIdentity -> String
renderProcessBirthIdentity identity =
  processBirthBootIdentity identity
    <> ":"
    <> show (processBirthStartTime identity)

parseProcessBirthIdentity :: String -> Maybe ProcessBirthIdentity
parseProcessBirthIdentity value = do
  if stringLengthAtMost maximumRenderedBirthIdentityLength value
    then Just ()
    else Nothing
  let (bootIdentity, startTimeSuffix) = break (== ':') value
  startTimeText <-
    case startTimeSuffix of
      ':' : suffix -> Just suffix
      _ -> Nothing
  startTime <- readMaybeWord64 startTimeText
  if validBootIdentity bootIdentity && startTime > 0
    then
      Just
        ProcessBirthIdentity
          { processBirthBootIdentity = bootIdentity,
            processBirthStartTime = startTime
          }
    else Nothing

readProcessBirthIdentity :: Integer -> IO (Maybe ProcessBirthIdentity)
readProcessBirthIdentity processId
  | not (validProcessId processId) = pure Nothing
#if defined(darwin_HOST_OS)
  | otherwise = do
      currentProcessId <- fromIntegral <$> getProcessID
      cachedIdentity <-
        if processId == currentProcessId
          then readCachedProcessIdentity currentProcessId
          else pure Nothing
      maybe
        (observeRegisteredProcessIdentity processId)
        (pure . Just)
        cachedIdentity
#elif defined(linux_HOST_OS)
  | otherwise = do
      maybeBootIdentity <- linuxBootIdentity
      maybeStartTime <- linuxProcessStartTime processId
      pure
        ( ProcessBirthIdentity
            <$> maybeBootIdentity
            <*> maybeStartTime
        )
#else
  | otherwise = pure Nothing
#endif

-- POSIX pid_t is signed on both supported hosts. Reject an out-of-range value
-- before converting it for a kernel API or interpolating it into procfs.
validProcessId :: Integer -> Bool
validProcessId processId =
  processId > 0 && processId <= 2147483647

validBootIdentity :: String -> Bool
validBootIdentity value =
  not (null value)
    && stringLengthAtMost maximumBootIdentityLength value
    && all
      (\character -> isAsciiAlphaNumeric character || character `elem` ("-_" :: String))
      value

readMaybeWord64 :: String -> Maybe Word64
readMaybeWord64 value
  | not (null value),
    stringLengthAtMost maximumWord64DecimalLength value,
    all isAsciiDigit value =
      parseWord64 value
  | otherwise = Nothing

parseWord64 :: String -> Maybe Word64
parseWord64 value =
  case reads value of
    [(parsed, "")] -> Just parsed
    _ -> Nothing

isAsciiAlphaNumeric :: Char -> Bool
isAsciiAlphaNumeric character =
  isAscii character && isAlphaNum character

isAsciiDigit :: Char -> Bool
isAsciiDigit character =
  isAscii character && isDigit character

stringLengthAtMost :: Int -> String -> Bool
stringLengthAtMost bound = go 0
  where
    go count _ | count > bound = False
    go _ [] = True
    go count (_ : suffix) = go (count + 1) suffix

maximumBootIdentityLength :: Int
maximumBootIdentityLength = 64

maximumWord64DecimalLength :: Int
maximumWord64DecimalLength = 20

maximumRenderedBirthIdentityLength :: Int
maximumRenderedBirthIdentityLength =
  maximumBootIdentityLength + 1 + maximumWord64DecimalLength

#if defined(darwin_HOST_OS)

data RegisteredProcessIdentity = RegisteredProcessIdentity
  { registeredProcessId :: !Integer,
    registeredBirthIdentity :: !ProcessBirthIdentity,
    registeredFileLock :: !FileLock
  }

{-# NOINLINE currentRegisteredProcessIdentity #-}
currentRegisteredProcessIdentity :: IORef (Maybe RegisteredProcessIdentity)
currentRegisteredProcessIdentity = unsafePerformIO (newIORef Nothing)

registerCurrentProcessIdentity :: IO ProcessBirthIdentity
registerCurrentProcessIdentity =
  mask_ $ do
    currentProcessId <- fromIntegral <$> getProcessID
    discardInheritedRegistration currentProcessId
    cachedIdentity <- readCachedProcessIdentity currentProcessId
    case cachedIdentity of
      Just identity -> pure identity
      Nothing -> do
        registryRoot <- requireProcessIdentityRegistry
        withRegistryMutationLock registryRoot $ do
          serializedIdentity <- readCachedProcessIdentity currentProcessId
          case serializedIdentity of
            Just identity -> pure identity
            Nothing -> do
              liveRegistrations <- reconcileRegistryEntries registryRoot
              when
                (any ((== currentProcessId) . fst) liveRegistrations)
                ( ioError
                    ( userError
                        "the current PID already has a live process-identity registration"
                    )
                )
              registered <-
                createRegisteredProcessIdentity registryRoot currentProcessId
              atomicWriteIORef
                currentRegisteredProcessIdentity
                (Just registered)
              pure (registeredBirthIdentity registered)

-- | Mint a Darwin birth token for a direct child while its designated owner
-- still holds unreaped-child authority. The supervisor keeps the lock across
-- the child's exec and releases it only after waitpid, so the registry identity
-- is not inherited by the target and cannot disappear at CLOEXEC.
registerOwnedChildProcessIdentity ::
  Integer ->
  IO RegisteredProcessIdentity
registerOwnedChildProcessIdentity processId = do
  unless
    (validProcessId processId)
    (ioError (userError "owned child registration requires a valid PID"))
  registryRoot <- requireProcessIdentityRegistry
  withRegistryMutationLock registryRoot $ do
    liveRegistrations <- reconcileRegistryEntries registryRoot
    when
      (any ((== processId) . fst) liveRegistrations)
      (ioError (userError "owned child PID already has a live registry identity"))
    createRegisteredProcessIdentity registryRoot processId

registeredProcessIdentity ::
  RegisteredProcessIdentity ->
  (Integer, ProcessBirthIdentity)
registeredProcessIdentity registered =
  (registeredProcessId registered, registeredBirthIdentity registered)

releaseRegisteredProcessIdentity ::
  RegisteredProcessIdentity ->
  IO ()
releaseRegisteredProcessIdentity =
  unlockFile . registeredFileLock

-- | A @forkProcess@ child receives a duplicate of the parent's file descriptor.
-- This operation uses no potentially locked-at-fork userspace mutex. Closing
-- the child's duplicate leaves the parent's open descriptor, and therefore its
-- kernel lock, intact while preventing the child from extending the parent's
-- registration lifetime.
dropInheritedProcessIdentity :: IO ()
dropInheritedProcessIdentity =
  mask_ $ do
    inherited <-
      atomicModifyIORef' currentRegisteredProcessIdentity $ \current ->
        (Nothing, current)
    mapM_ (unlockFile . registeredFileLock) inherited

readCachedProcessIdentity :: Integer -> IO (Maybe ProcessBirthIdentity)
readCachedProcessIdentity currentProcessId = do
  current <- readIORef currentRegisteredProcessIdentity
  pure $ do
    registered <- current
    if registeredProcessId registered == currentProcessId
      then Just (registeredBirthIdentity registered)
      else Nothing

discardInheritedRegistration :: Integer -> IO ()
discardInheritedRegistration currentProcessId = do
  inherited <-
    atomicModifyIORef' currentRegisteredProcessIdentity $ \current ->
      case current of
        Just registered
          | registeredProcessId registered /= currentProcessId ->
              (Nothing, Just registered)
        _ -> (current, Nothing)
  mapM_ (unlockFile . registeredFileLock) inherited

createRegisteredProcessIdentity ::
  FilePath ->
  Integer ->
  IO RegisteredProcessIdentity
createRegisteredProcessIdentity registryRoot processId =
  createCandidate 0
  where
    createCandidate attempt
      | attempt >= maximumIdentityCreationAttempts =
          ioError
            (userError "process-identity token allocation exhausted its retry bound")
      | otherwise = do
          identity <- randomProcessBirthIdentity
          pendingNonce <- randomRegistryNonce
          candidate <-
            tryCreateRegisteredProcessIdentity
              registryRoot
              processId
              identity
              pendingNonce
              (const (pure ()))
          maybe
            (createCandidate (attempt + 1))
            pure
            candidate

tryCreateRegisteredProcessIdentity ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  String ->
  (PublicationTestPoint -> IO ()) ->
  IO (Maybe RegisteredProcessIdentity)
tryCreateRegisteredProcessIdentity
  registryRoot
  processId
  identity
  pendingNonce
  publicationHook = do
  let pendingPath =
        registryRoot
          </> renderPendingRegistryEntry pendingNonce
      finalPath =
        registryRoot
          </> renderRegistryEntry processId identity
  created <- createPrivateRegularFile pendingPath
  if not created
    then pure Nothing
    else do
      pendingStatus <- requirePrivateRegularFile pendingPath
      maybeLock <- tryLockFile pendingPath Exclusive
      case maybeLock of
        Nothing ->
          ioError
            ( userError
                "a newly created process-identity pending inode was already locked"
            )
        Just fileLock -> do
          installResult <-
            try
              ( installRegisteredIdentity
                  registryRoot
                  pendingPath
                  finalPath
                  pendingStatus
                  publicationHook
              ) ::
              IO (Either IOException ())
          case installResult of
            Right () ->
              pure
                ( Just
                    RegisteredProcessIdentity
                      { registeredProcessId = processId,
                        registeredBirthIdentity = identity,
                        registeredFileLock = fileLock
                      }
                )
            Left failure -> do
              cleanupResult <-
                try
                  ( cleanupRegistrationCandidate
                      registryRoot
                      pendingStatus
                      pendingPath
                      finalPath
                      `finally` unlockFile fileLock
                  ) ::
                  IO (Either IOException ())
              case cleanupResult of
                Left _ -> pure ()
                Right () -> pure ()
              if isAlreadyExistsError failure
                then pure Nothing
                else ioError failure

installRegisteredIdentity ::
  FilePath ->
  FilePath ->
  FilePath ->
  FileStatus ->
  (PublicationTestPoint -> IO ()) ->
  IO ()
installRegisteredIdentity
  registryRoot
  pendingPath
  finalPath
  pendingStatus
  publicationHook = do
  lockedPendingStatus <- requirePrivateRegularFile pendingPath
  requireSameRegistryInode
    "pending inode changed before publication"
    pendingStatus
    lockedPendingStatus
  publicationHook PendingInodeLocked
  createLink pendingPath finalPath
  linkedFinalStatus <- requirePrivateRegularFile finalPath
  requireSameRegistryInode
    "published process-identity link names the wrong inode"
    pendingStatus
    linkedFinalStatus
  publicationHook FinalLinkInstalled
  removeFile pendingPath
  installedFinalStatus <- requirePrivateRegularFile finalPath
  requireSameRegistryInode
    "process-identity final inode changed during publication"
    pendingStatus
    installedFinalStatus
  synchroniseDirectory registryRoot

cleanupRegistrationCandidate ::
  FilePath ->
  FileStatus ->
  FilePath ->
  FilePath ->
  IO ()
cleanupRegistrationCandidate registryRoot expectedStatus pendingPath finalPath = do
  finalRemoved <- removePathIfSameInode expectedStatus finalPath
  pendingRemoved <- removePathIfSameInode expectedStatus pendingPath
  when (finalRemoved || pendingRemoved) (synchroniseDirectory registryRoot)

observeRegisteredProcessIdentity ::
  Integer ->
  IO (Maybe ProcessBirthIdentity)
observeRegisteredProcessIdentity processId = do
  registryResult <-
    try requireProcessIdentityRegistry ::
      IO (Either IOException FilePath)
  case registryResult of
    Left _ -> pure Nothing
    Right registryRoot -> do
      observation <-
        try
          ( withRegistryMutationLock registryRoot $ do
              observations <- reconcileRegistryEntries registryRoot
              pure
                [ identity
                | (registeredProcessIdValue, identity) <- observations,
                  registeredProcessIdValue == processId
                ]
          ) ::
          IO (Either IOException [ProcessBirthIdentity])
      pure $
        case observation of
          Right [identity] -> Just identity
          _ -> Nothing

reconcileRegistryEntries ::
  FilePath ->
  IO [(Integer, ProcessBirthIdentity)]
reconcileRegistryEntries registryRoot = do
  entries <- boundedRegistryEntries registryRoot
  (liveRegistrations, removedEntry) <-
    foldM reconcile ([], False) entries
  when removedEntry (synchroniseDirectory registryRoot)
  pure (reverse liveRegistrations)
  where
    reconcile current@(liveRegistrations, removedEntry) entry
      | entry == registryMutationLockName = do
          _ <- requirePrivateRegularFile (registryRoot </> entry)
          pure current
      | ".pending-v1." `List.isPrefixOf` entry =
          if parsePendingRegistryEntry entry
            then do
              locked <- inspectAndRetireRegistryPath (registryRoot </> entry)
              pure (liveRegistrations, removedEntry || not locked)
            else
              ioError
                (userError ("malformed process-identity pending entry: " <> entry))
      | otherwise =
          case parseRegistryEntry entry of
            Nothing ->
              ioError
                (userError ("malformed process-identity registry entry: " <> entry))
            Just registration -> do
              locked <- inspectAndRetireRegistryPath (registryRoot </> entry)
              pure
                ( if locked
                    then registration : liveRegistrations
                    else liveRegistrations,
                  removedEntry || not locked
                )

inspectAndRetireRegistryPath :: FilePath -> IO Bool
inspectAndRetireRegistryPath path = do
  initialStatus <- requirePrivateRegularFile path
  maybeLock <- tryLockFile path Exclusive
  case maybeLock of
    Nothing -> do
      observedStatus <- requirePrivateRegularFile path
      requireSameRegistryInode
        "locked process-identity path changed during observation"
        initialStatus
        observedStatus
      pure True
    Just staleLock ->
      bracket (pure staleLock) unlockFile $ \_ -> do
        staleStatus <- requirePrivateRegularFile path
        requireSameRegistryInode
          "stale process-identity path changed during cleanup"
          initialStatus
          staleStatus
        removeFile path
        pure False

requireProcessIdentityRegistry :: IO FilePath
requireProcessIdentityRegistry = do
  effectiveUser <- getEffectiveUserID
  let registryRoot =
        "/tmp/infernix-process-identities-" <> show effectiveUser
  requireProcessIdentityRegistryAt registryRoot
  pure registryRoot

-- The effective UID is the registry trust boundary. The private directory
-- excludes other UIDs; every entry is still lstat-checked before filelock is
-- allowed to reopen it so a same-UID bug cannot silently turn a symlink,
-- non-regular inode, or widened mode into process identity evidence.
requireProcessIdentityRegistryAt :: FilePath -> IO ()
requireProcessIdentityRegistryAt registryRoot = do
  effectiveUser <- getEffectiveUserID
  createResult <-
    try (PosixDirectory.createDirectory registryRoot ownerModes)
  case createResult of
    Right () -> pure ()
    Left failure
      | isAlreadyExistsError failure -> pure ()
      | otherwise -> ioError failure
  status <- getSymbolicLinkStatus registryRoot
  unless
    ( isDirectory status
        && fileOwner status == effectiveUser
        && fileMode status .&. (ownerModes .|. groupModes .|. otherModes)
          == ownerModes
    )
    ( ioError
        ( userError
            ( "process-identity registry must be a real owner-0700 directory: "
                <> registryRoot
            )
        )
    )

prepareProcessIdentityRegistryForTest :: FilePath -> IO ()
prepareProcessIdentityRegistryForTest =
  requireProcessIdentityRegistryAt

registerProcessIdentityForTest ::
  FilePath ->
  Integer ->
  IO RegisteredProcessIdentity
registerProcessIdentityForTest registryRoot processId = do
  unless
    (validProcessId processId)
    (ioError (userError "test process identity requires a valid positive PID"))
  requireProcessIdentityRegistryAt registryRoot
  withRegistryMutationLock registryRoot $ do
    liveRegistrations <- reconcileRegistryEntries registryRoot
    when
      (any ((== processId) . fst) liveRegistrations)
      (ioError (userError "test PID already has a live registry identity"))
    createRegisteredProcessIdentity registryRoot processId

publishProcessIdentityCandidateForTest ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  String ->
  IO (Maybe RegisteredProcessIdentity)
publishProcessIdentityCandidateForTest registryRoot processId identity pendingNonce =
  publishProcessIdentityCandidateWithHookForTest
    registryRoot
    processId
    identity
    pendingNonce
    (const (pure ()))

publishProcessIdentityCandidateWithHookForTest ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  String ->
  (PublicationTestPoint -> IO ()) ->
  IO (Maybe RegisteredProcessIdentity)
publishProcessIdentityCandidateWithHookForTest
  registryRoot
  processId
  identity
  pendingNonce
  publicationHook = do
  unless
    ( validProcessId processId
        && parseRegistryToken (renderRegistryToken identity) == Just identity
        && parsePendingRegistryEntry
          (renderPendingRegistryEntry pendingNonce)
    )
    (ioError (userError "invalid process-identity test candidate"))
  requireProcessIdentityRegistryAt registryRoot
  withRegistryMutationLock registryRoot
    ( tryCreateRegisteredProcessIdentity
        registryRoot
        processId
        identity
        pendingNonce
        publicationHook
    )

releaseProcessIdentityForTest :: RegisteredProcessIdentity -> IO ()
releaseProcessIdentityForTest =
  releaseRegisteredProcessIdentity

registeredProcessIdentityForTest ::
  RegisteredProcessIdentity ->
  ProcessBirthIdentity
registeredProcessIdentityForTest =
  registeredBirthIdentity

observeProcessIdentityForTest ::
  FilePath ->
  Integer ->
  IO (Maybe ProcessBirthIdentity)
observeProcessIdentityForTest registryRoot processId = do
  observation <-
    try
      ( do
          requireProcessIdentityRegistryAt registryRoot
          withRegistryMutationLock registryRoot $ do
            liveRegistrations <- reconcileRegistryEntries registryRoot
            pure
              [ identity
              | (registeredProcessIdValue, identity) <- liveRegistrations,
                registeredProcessIdValue == processId
              ]
      ) ::
      IO (Either IOException [ProcessBirthIdentity])
  pure $
    case observation of
      Right [identity] -> Just identity
      _ -> Nothing

reconcileProcessIdentityRegistryForTest ::
  FilePath ->
  IO [(Integer, ProcessBirthIdentity)]
reconcileProcessIdentityRegistryForTest registryRoot = do
  requireProcessIdentityRegistryAt registryRoot
  withRegistryMutationLock registryRoot
    (reconcileRegistryEntries registryRoot)

renderRegistryEntryForTest ::
  Integer ->
  ProcessBirthIdentity ->
  FilePath
renderRegistryEntryForTest =
  renderRegistryEntry

renderPendingRegistryEntryForTest :: String -> FilePath
renderPendingRegistryEntryForTest =
  renderPendingRegistryEntry

maximumRegistryEntriesForTest :: Int
maximumRegistryEntriesForTest =
  maximumRegistryEntries

maximumRegistryBasenameLengthForTest :: Int
maximumRegistryBasenameLengthForTest =
  maximumRegistryBasenameLength

withCurrentProcessIdentityRegistryLockForTest :: IO a -> IO a
withCurrentProcessIdentityRegistryLockForTest action = do
  registryRoot <- requireProcessIdentityRegistry
  withRegistryMutationLock registryRoot action

withRegistryMutationLock :: FilePath -> IO a -> IO a
withRegistryMutationLock registryRoot action = do
  let mutationLockPath = registryRoot </> registryMutationLockName
  _ <- createPrivateRegularFile mutationLockPath
  initialStatus <- requirePrivateRegularFile mutationLockPath
  maybeLock <-
    timeout
      registryMutationLockTimeoutMicros
      ( do
          registryLock <- lockFile mutationLockPath Exclusive
          ( do
              lockedStatus <- requirePrivateRegularFile mutationLockPath
              requireSameRegistryInode
                "process-identity registry lock inode changed during acquisition"
                initialStatus
                lockedStatus
              pure registryLock
            )
            `onException` unlockFile registryLock
      )
  case maybeLock of
    Nothing ->
      ioError
        (userError "process-identity registry mutation lock acquisition timed out")
    Just registryLock ->
      bracket (pure registryLock) unlockFile (const action)

boundedRegistryEntries :: FilePath -> IO [FilePath]
boundedRegistryEntries registryRoot =
  bracket
    (PosixDirectory.openDirStream registryRoot)
    PosixDirectory.closeDirStream
    (\directoryStream -> collect directoryStream 0 [])
  where
    collect directoryStream entryCount entries = do
      entry <- PosixDirectory.readDirStream directoryStream
      case entry of
        "" -> pure (reverse entries)
        "." -> collect directoryStream entryCount entries
        ".." -> collect directoryStream entryCount entries
        _
          | entryCount >= maximumRegistryEntries ->
              ioError
                (userError "process-identity registry exceeds its entry-count bound")
          | otherwise -> do
              validateRegistryBasename entry
              collect directoryStream (entryCount + 1) (entry : entries)

validateRegistryBasename :: FilePath -> IO ()
validateRegistryBasename entry =
  unless
    ( not (null entry)
        && stringLengthAtMost maximumRegistryBasenameLength entry
        && all validRegistryBasenameCharacter entry
    )
    (ioError (userError ("invalid process-identity registry basename: " <> entry)))

validRegistryBasenameCharacter :: Char -> Bool
validRegistryBasenameCharacter character =
  isAsciiAlphaNumeric character || character `elem` (".-_" :: String)

renderRegistryEntry :: Integer -> ProcessBirthIdentity -> FilePath
renderRegistryEntry processId identity =
  "process-v1."
    <> show processId
    <> "."
    <> renderRegistryToken identity
    <> ".lock"

parseRegistryEntry :: FilePath -> Maybe (Integer, ProcessBirthIdentity)
parseRegistryEntry entry =
  case splitOnPeriod entry of
    ["process-v1", processIdText, token, "lock"] -> do
      processId <- readMaybeInteger processIdText
      identity <- parseRegistryToken token
      if validProcessId processId
        then Just (processId, identity)
        else Nothing
    _ -> Nothing

renderPendingRegistryEntry :: String -> FilePath
renderPendingRegistryEntry nonce =
  ".pending-v1." <> nonce <> ".lock"

parsePendingRegistryEntry :: FilePath -> Bool
parsePendingRegistryEntry entry =
  case splitOnPeriod entry of
    ["", "pending-v1", nonce, "lock"] ->
      length nonce == registryPendingNonceLength
        && all isLowerHexDigit nonce
    _ -> False

renderRegistryToken :: ProcessBirthIdentity -> String
renderRegistryToken identity =
  processBirthBootIdentity identity
    <> "-"
    <> show (processBirthStartTime identity)

parseRegistryToken :: String -> Maybe ProcessBirthIdentity
parseRegistryToken token = do
  let (randomPrefix, randomSuffix) = break (== '-') token
  randomValue <-
    case randomSuffix of
      '-' : value -> readMaybeWord64 value
      _ -> Nothing
  if
      length randomPrefix == registryTokenPrefixLength
        && all isLowerHexDigit randomPrefix
        && not (null randomSuffix)
        && all isAsciiDigit (drop 1 randomSuffix)
        && randomValue > 0
    then
      Just
        ProcessBirthIdentity
          { processBirthBootIdentity = randomPrefix,
            processBirthStartTime = randomValue
          }
    else Nothing

randomProcessBirthIdentity :: IO ProcessBirthIdentity
randomProcessBirthIdentity = do
  entropy <- getEntropy registryTokenEntropyBytes
  let (prefixBytes, suffixBytes) =
        ByteString.splitAt registryTokenPrefixBytes entropy
      randomPrefix =
        Text.unpack (TextEncoding.decodeUtf8 (Base16.encode prefixBytes))
      randomSuffix =
        ByteString.foldl'
          (\value byte -> value `shiftL` 8 .|. fromIntegral byte)
          0
          suffixBytes
  if
      ByteString.length entropy == registryTokenEntropyBytes
        && randomSuffix > 0
    then
      pure
        ProcessBirthIdentity
          { processBirthBootIdentity = randomPrefix,
            processBirthStartTime = randomSuffix
          }
    else randomProcessBirthIdentity

randomRegistryNonce :: IO String
randomRegistryNonce = do
  entropy <- getEntropy registryPendingNonceBytes
  if ByteString.length entropy == registryPendingNonceBytes
    then pure (renderEntropyHex entropy)
    else randomRegistryNonce

renderEntropyHex :: ByteString.ByteString -> String
renderEntropyHex =
  Text.unpack . TextEncoding.decodeUtf8 . Base16.encode

isLowerHexDigit :: Char -> Bool
isLowerHexDigit character =
  isAsciiDigit character || character >= 'a' && character <= 'f'

splitOnPeriod :: String -> [String]
splitOnPeriod value =
  case break (== '.') value of
    (component, []) -> [component]
    (component, _ : suffix) -> component : splitOnPeriod suffix

readMaybeInteger :: String -> Maybe Integer
readMaybeInteger value =
  if
      not (null value)
        && stringLengthAtMost maximumProcessIdDecimalLength value
        && all isAsciiDigit value
    then
      case reads value of
        [(parsed, "")] -> Just parsed
        _ -> Nothing
    else Nothing

createPrivateRegularFile :: FilePath -> IO Bool
createPrivateRegularFile path = do
  creationResult <-
    try
      ( bracket
          ( openFd
              path
              WriteOnly
              defaultFileFlags
                { exclusive = True,
                  nofollow = True,
                  creat = Just privateRegistryFileMode,
                  cloexec = True
                }
          )
          closeFd
          (const (pure ()))
      ) ::
      IO (Either IOException ())
  case creationResult of
    Right () -> pure True
    Left failure
      | isAlreadyExistsError failure -> pure False
      | otherwise -> ioError failure

requirePrivateRegularFile :: FilePath -> IO FileStatus
requirePrivateRegularFile path = do
  effectiveUser <- getEffectiveUserID
  status <- getSymbolicLinkStatus path
  unless
    ( isRegularFile status
        && fileOwner status == effectiveUser
        && fileMode status .&. registryPermissionMask
          == privateRegistryFileMode
    )
    ( ioError
        ( userError
            ( "process-identity registry entry must be a real owner-0600 file: "
                <> path
            )
        )
    )
  pure status

requireSameRegistryInode :: String -> FileStatus -> FileStatus -> IO ()
requireSameRegistryInode failureMessage expectedStatus observedStatus =
  unless
    ( deviceID expectedStatus == deviceID observedStatus
        && fileID expectedStatus == fileID observedStatus
    )
    (ioError (userError failureMessage))

removePathIfSameInode :: FileStatus -> FilePath -> IO Bool
removePathIfSameInode expectedStatus path = do
  statusResult <-
    try (getSymbolicLinkStatus path) ::
      IO (Either IOException FileStatus)
  case statusResult of
    Left failure
      | isDoesNotExistError failure -> pure False
      | otherwise -> ioError failure
    Right status
      | deviceID expectedStatus == deviceID status
          && fileID expectedStatus == fileID status -> do
          removeFile path
          pure True
      | otherwise -> pure False

synchroniseDirectory :: FilePath -> IO ()
synchroniseDirectory directoryPath =
  bracket
    (openFd directoryPath ReadOnly defaultFileFlags)
    closeFd
    fileSynchronise

registryMutationLockName :: FilePath
registryMutationLockName = ".registry.lock"

registryMutationLockTimeoutMicros :: Int
registryMutationLockTimeoutMicros = 5000000

maximumRegistryEntries :: Int
maximumRegistryEntries = 4096

maximumRegistryBasenameLength :: Int
maximumRegistryBasenameLength = 160

maximumIdentityCreationAttempts :: Int
maximumIdentityCreationAttempts = 32

registryTokenPrefixBytes :: Int
registryTokenPrefixBytes = 16

registryTokenPrefixLength :: Int
registryTokenPrefixLength = registryTokenPrefixBytes * 2

registryTokenEntropyBytes :: Int
registryTokenEntropyBytes = registryTokenPrefixBytes + 8

registryPendingNonceBytes :: Int
registryPendingNonceBytes = 32

registryPendingNonceLength :: Int
registryPendingNonceLength = registryPendingNonceBytes * 2

maximumProcessIdDecimalLength :: Int
maximumProcessIdDecimalLength = 10

privateRegistryFileMode :: FileMode
privateRegistryFileMode = ownerReadMode .|. ownerWriteMode

registryPermissionMask :: FileMode
registryPermissionMask = ownerModes .|. groupModes .|. otherModes

#elif defined(linux_HOST_OS)

registerCurrentProcessIdentity :: IO ProcessBirthIdentity
registerCurrentProcessIdentity = do
  currentProcessId <- fromIntegral <$> getProcessID
  readProcessBirthIdentity currentProcessId
    >>= maybe
      (ioError (userError "Linux procfs did not expose the current process birth identity"))
      pure

dropInheritedProcessIdentity :: IO ()
dropInheritedProcessIdentity = pure ()

linuxBootIdentity :: IO (Maybe String)
linuxBootIdentity = do
  maybeContents <- readStrictFile "/proc/sys/kernel/random/boot_id"
  pure $ do
    contents <- maybeContents
    let value = trim (ByteString8.unpack contents)
    if validBootIdentity value
      then Just value
      else Nothing

linuxProcessStartTime :: Integer -> IO (Maybe Word64)
linuxProcessStartTime processId = do
  maybeContents <-
    readStrictFile
      ("/proc/" <> show processId <> "/stat")
  pure (maybeContents >>= parseLinuxProcessStartTime . ByteString8.unpack)

-- /proc/<pid>/stat field 2 is parenthesized and may itself contain spaces or
-- ')' characters. Split after its final ')' and then index fields relative to
-- field 3; field 22 (starttime) is therefore index 19.
parseLinuxProcessStartTime :: String -> Maybe Word64
parseLinuxProcessStartTime contents = do
  closingParenthesis <-
    case List.elemIndices ')' contents of
      [] -> Nothing
      indices -> Just (last indices)
  startTimeText <- atMay (words (drop (closingParenthesis + 1) contents)) 19
  startTime <- readMaybe startTimeText
  if startTime > 0
    then Just startTime
    else Nothing

readStrictFile :: FilePath -> IO (Maybe ByteString)
readStrictFile path = do
  result <-
    try (ByteString8.readFile path) ::
      IO (Either IOException ByteString)
  pure (either (const Nothing) Just result)

trim :: String -> String
trim = List.dropWhileEnd isSpace . dropWhile isSpace

atMay :: [a] -> Int -> Maybe a
atMay values index
  | index < 0 = Nothing
  | otherwise =
      case drop index values of
        value : _ -> Just value
        [] -> Nothing

#else

registerCurrentProcessIdentity :: IO ProcessBirthIdentity
registerCurrentProcessIdentity =
  ioError (userError "process birth identity is unavailable on this platform")

dropInheritedProcessIdentity :: IO ()
dropInheritedProcessIdentity = pure ()

#endif
