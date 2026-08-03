{-# LANGUAGE CPP #-}
{-# LANGUAGE TypeApplications #-}

module ProcessIdentitySpec (runProcessIdentityTests) where

import Control.Monad (unless)
import Data.Maybe (isNothing)
import Data.Word (Word64)
import Infernix.ProcessIdentity
  ( ProcessBirthIdentity (..),
    parseProcessBirthIdentity,
    renderProcessBirthIdentity,
  )

#if defined(darwin_HOST_OS)
import Control.Concurrent (forkIO)
import Control.Concurrent.MVar qualified as MVar
import Control.Exception (IOException, SomeException, finally, try)
import Control.Monad (forM_, replicateM)
import Data.Bits ((.|.))
import Data.ByteString.Char8 qualified as ByteString8
import Data.List (isInfixOf, isPrefixOf)
import Data.Maybe (isJust)
import Infernix.ProcessIdentity
  ( dropInheritedProcessIdentity,
    readProcessBirthIdentity,
    registerCurrentProcessIdentity,
  )
import Infernix.ProcessIdentity.Internal
  ( PublicationTestPoint (..),
    maximumRegistryBasenameLengthForTest,
    maximumRegistryEntriesForTest,
    observeProcessIdentityForTest,
    prepareProcessIdentityRegistryForTest,
    publishProcessIdentityCandidateForTest,
    publishProcessIdentityCandidateWithHookForTest,
    reconcileProcessIdentityRegistryForTest,
    registeredProcessIdentityForTest,
    registerProcessIdentityForTest,
    releaseProcessIdentityForTest,
    renderPendingRegistryEntryForTest,
    renderRegistryEntryForTest,
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesDirectoryExist,
    doesFileExist,
    listDirectory,
    removeFile,
    removePathForcibly,
  )
import System.Exit (ExitCode (..))
import System.FilePath (takeDirectory, (</>))
import System.IO.Error (isDoesNotExistError)
import System.Posix.ByteString qualified as PosixByteString
import System.Posix.Directory qualified as PosixDirectory
import System.Posix.Files
  ( createSymbolicLink,
    groupReadMode,
    otherReadMode,
    ownerModes,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
  )
import System.Posix.IO
  ( OpenFileFlags
      ( cloexec,
        creat,
        exclusive,
        nofollow
      ),
    OpenMode (WriteOnly),
    closeFd,
    createPipe,
    defaultFileFlags,
    openFd,
  )
import System.Posix.Process
  ( ProcessStatus (Exited, Stopped),
    exitImmediately,
    forkProcess,
    getProcessID,
    getProcessStatus,
  )
import System.Posix.Signals
  ( sigKILL,
    sigSTOP,
    signalProcess,
  )
import System.Posix.Types (Fd, FileMode)
import System.Timeout (timeout)
import Numeric (showHex)
#endif

runProcessIdentityTests :: FilePath -> IO ()
runProcessIdentityTests testRoot = do
  let roundTripIdentity =
        ProcessBirthIdentity
          { processBirthBootIdentity = "boot_identity-123",
            processBirthStartTime = maxBound `div` 2
          }
  assert
    ( parseProcessBirthIdentity
        (renderProcessBirthIdentity roundTripIdentity)
        == Just roundTripIdentity
    )
    "process birth identities round-trip through their bounded wire representation"
  assert
    (isNothing (parseProcessBirthIdentity (replicate 65 'a' <> ":1")))
    "process birth identity parsing rejects an oversized boot token"
  assert
    ( isNothing
        ( parseProcessBirthIdentity
            ("boot:" <> show (toInteger (maxBound @Word64) + 1))
        )
    )
    "process birth identity parsing rejects a Word64 overflow"
  assert
    (isNothing (parseProcessBirthIdentity "boot:1:2"))
    "process birth identity parsing rejects trailing token data"
#if defined(darwin_HOST_OS)
  runDarwinProcessIdentityTests testRoot
#else
  testRoot `seq` pure ()
#endif

assert :: Bool -> String -> IO ()
assert condition message =
  unless condition (ioError (userError message))

#if defined(darwin_HOST_OS)

runDarwinProcessIdentityTests :: FilePath -> IO ()
runDarwinProcessIdentityTests testRoot = do
  resetDirectory testRoot
  ( do
      testSameProcessRegistration
      testIsolatedRegistry (testRoot </> "isolated")
      testRegistryCorruptionRefusal testRoot
      testRegistryEntryCountBound (testRoot </> "entry-count")
      testInterruptedPublications testRoot
      testCrossProcessDeath
      testInheritedStoppedChildRelease
    )
    `finally` ignoreMissingPath (removePathForcibly testRoot)

testSameProcessRegistration :: IO ()
testSameProcessRegistration = do
  firstIdentity <- registerCurrentProcessIdentity
  secondIdentity <- registerCurrentProcessIdentity
  currentProcessId <- fromIntegral <$> getProcessID
  observedIdentity <- readProcessBirthIdentity currentProcessId
  assert
    ( firstIdentity == secondIdentity
        && observedIdentity == Just firstIdentity
    )
    "explicit current-process registration is idempotent and self-observation returns its cached identity"

testIsolatedRegistry :: FilePath -> IO ()
testIsolatedRegistry registryRoot = do
  resetRegistry registryRoot
  let randomProcessId = 2000000000
      processId = 2000000001
      firstIdentity = testIdentity 'a' 1
      secondIdentity = testIdentity 'b' 2
      firstNonce = replicate 64 '1'
      secondNonce = replicate 64 '2'
      thirdNonce = replicate 64 '3'
  randomRegistration <-
    registerProcessIdentityForTest registryRoot randomProcessId
  let randomIdentity =
        registeredProcessIdentityForTest randomRegistration
  randomObservation <-
    observeProcessIdentityForTest registryRoot randomProcessId
  assert
    (randomObservation == Just randomIdentity)
    "entropy-backed registration publishes exactly its opaque returned identity"
  releaseProcessIdentityForTest randomRegistration
  randomAbsence <-
    observeProcessIdentityForTest registryRoot randomProcessId
  assert
    (randomAbsence == Nothing)
    "releasing an isolated registration lets the next scan retire it"
  firstCandidate <-
    publishProcessIdentityCandidateForTest
      registryRoot
      processId
      firstIdentity
      firstNonce
  assert (isJust firstCandidate) "a locked pending inode publishes one final registry token"
  observedFirst <- observeProcessIdentityForTest registryRoot processId
  assert
    (observedFirst == Just firstIdentity)
    "an exact locked final registry token is observable"
  finalCollision <-
    publishProcessIdentityCandidateForTest
      registryRoot
      processId
      firstIdentity
      secondNonce
  assert
    (not (isJust finalCollision))
    "atomic no-overwrite publication rejects a final-name collision"
  observedAfterCollision <- observeProcessIdentityForTest registryRoot processId
  assert
    (observedAfterCollision == Just firstIdentity)
    "a final-name collision leaves the original locked identity unchanged"
  let pendingCollisionPath =
        registryRoot </> renderPendingRegistryEntryForTest thirdNonce
  createTestFile pendingCollisionPath privateFileMode
  pendingCollision <-
    publishProcessIdentityCandidateForTest
      registryRoot
      processId
      secondIdentity
      thirdNonce
  pendingCollisionStillExists <- doesFileExist pendingCollisionPath
  assert
    (not (isJust pendingCollision) && pendingCollisionStillExists)
    "exclusive pending creation cannot adopt or overwrite an existing inode"
  removeFile pendingCollisionPath
  secondCandidate <-
    publishProcessIdentityCandidateForTest
      registryRoot
      processId
      secondIdentity
      (replicate 64 '4')
  assert (isJust secondCandidate) "the test registry can hold a second exact locked token"
  ambiguousObservation <- observeProcessIdentityForTest registryRoot processId
  assert
    (ambiguousObservation == Nothing)
    "multiple locked tokens for one PID fail closed as ambiguous"
  concurrentResults <- concurrentObservations registryRoot processId 16
  assert
    (all (== Nothing) concurrentResults)
    "concurrent registry scans serialize and agree on the ambiguous result"
  mapM_ releaseProcessIdentityForTest firstCandidate
  mapM_ releaseProcessIdentityForTest secondCandidate
  absentAfterRelease <- observeProcessIdentityForTest registryRoot processId
  assert
    (absentAfterRelease == Nothing)
    "unlocked final tokens are retired before absence is reported"
  liveAfterRelease <- reconcileProcessIdentityRegistryForTest registryRoot
  assert
    (null liveAfterRelease)
    "stale cleanup leaves no live registration evidence"

testRegistryCorruptionRefusal :: FilePath -> IO ()
testRegistryCorruptionRefusal testRoot = do
  testMalformedEntry (testRoot </> "malformed")
  testOversizedEntry (testRoot </> "oversized")
  testSymlinkEntry (testRoot </> "symlink")
  testWrongTypeEntry (testRoot </> "wrong-type")
  testWrongModeEntry (testRoot </> "wrong-mode")

testMalformedEntry :: FilePath -> IO ()
testMalformedEntry registryRoot = do
  resetRegistry registryRoot
  let malformedPath = registryRoot </> "malformed.lock"
  createTestFile malformedPath privateFileMode
  observation <- observeProcessIdentityForTest registryRoot 2000000002
  malformedStillExists <- doesFileExist malformedPath
  assert
    (observation == Nothing && malformedStillExists)
    "a malformed basename fails closed without being adopted or deleted"

testOversizedEntry :: FilePath -> IO ()
testOversizedEntry registryRoot = do
  resetRegistry registryRoot
  let oversizedPath =
        registryRoot
          </> replicate (maximumRegistryBasenameLengthForTest + 1) 'a'
  createTestFile oversizedPath privateFileMode
  observation <- observeProcessIdentityForTest registryRoot 2000000003
  oversizedStillExists <- doesFileExist oversizedPath
  assert
    (observation == Nothing && oversizedStillExists)
    "an oversized registry basename is rejected before token parsing"

testSymlinkEntry :: FilePath -> IO ()
testSymlinkEntry registryRoot = do
  resetRegistry registryRoot
  let processId = 2000000004
      identity = testIdentity 'c' 3
      targetPath = registryRoot </> "symlink-target"
      entryPath = registryRoot </> renderRegistryEntryForTest processId identity
  createTestFile targetPath privateFileMode
  createSymbolicLink "symlink-target" entryPath
  observation <- observeProcessIdentityForTest registryRoot processId
  symlinkStillExists <- doesFileExist entryPath
  targetStillExists <- doesFileExist targetPath
  assert
    (observation == Nothing && symlinkStillExists && targetStillExists)
    "lstat rejects a symlink before filelock can reopen its target"

testWrongTypeEntry :: FilePath -> IO ()
testWrongTypeEntry registryRoot = do
  resetRegistry registryRoot
  let processId = 2000000005
      entryPath =
        registryRoot
          </> renderRegistryEntryForTest processId (testIdentity 'd' 4)
  PosixDirectory.createDirectory entryPath ownerModes
  observation <- observeProcessIdentityForTest registryRoot processId
  entryStillExists <- doesDirectoryExist entryPath
  assert
    (observation == Nothing && entryStillExists)
    "lstat rejects a non-regular registry inode before locking"

testWrongModeEntry :: FilePath -> IO ()
testWrongModeEntry registryRoot = do
  resetRegistry registryRoot
  let processId = 2000000006
      entryPath =
        registryRoot
          </> renderRegistryEntryForTest processId (testIdentity 'e' 5)
  createTestFile
    entryPath
    (privateFileMode .|. groupReadMode .|. otherReadMode)
  setFileMode
    entryPath
    (privateFileMode .|. groupReadMode .|. otherReadMode)
  observation <- observeProcessIdentityForTest registryRoot processId
  entryStillExists <- doesFileExist entryPath
  assert
    (observation == Nothing && entryStillExists)
    "a widened registry file mode is refused before locking"

testRegistryEntryCountBound :: FilePath -> IO ()
testRegistryEntryCountBound registryRoot = do
  resetRegistry registryRoot
  forM_ [1 .. maximumRegistryEntriesForTest] $ \entryIndex ->
    createTestFile
      ( registryRoot
          </> renderPendingRegistryEntryForTest
            (leftPad 64 '0' (showHex entryIndex ""))
      )
      privateFileMode
  reconciliation <-
    try @IOException (reconcileProcessIdentityRegistryForTest registryRoot)
  let reconciliationReachedEntryCountBound =
        case reconciliation of
          Left failure ->
            "entry-count bound" `isInfixOf` show failure
          Right _ -> False
  assert
    reconciliationReachedEntryCountBound
    "registry enumeration stops at its entry-count bound"

testInterruptedPublications :: FilePath -> IO ()
testInterruptedPublications testRoot = do
  testInterruptedPublication
    (testRoot </> "pending-owner-death")
    2000000008
    (testIdentity '8' 8)
    (replicate 64 '8')
    PendingInodeLocked
  testInterruptedPublication
    (testRoot </> "linked-owner-death")
    2000000009
    (testIdentity '9' 9)
    (replicate 64 '9')
    FinalLinkInstalled

testInterruptedPublication ::
  FilePath ->
  Integer ->
  ProcessBirthIdentity ->
  String ->
  PublicationTestPoint ->
  IO ()
testInterruptedPublication
  registryRoot
  processId
  identity
  pendingNonce
  requestedPoint = do
    resetRegistry registryRoot
    (readyReader, readyWriter) <- createPipe
    (blockReader, blockWriter) <- createPipe
    publisherPid <-
      forkProcess $ do
        closeFd readyReader
        closeFd blockWriter
        dropInheritedProcessIdentity
        publicationResult <-
          try @SomeException
            ( publishProcessIdentityCandidateWithHookForTest
                registryRoot
                processId
                identity
                pendingNonce
                ( \observedPoint ->
                    whenPoint requestedPoint observedPoint $ do
                      writeLine readyWriter (show observedPoint)
                      _ <- PosixByteString.fdRead blockReader 1
                      pure ()
                )
            )
        closeFd readyWriter
        closeFd blockReader
        exitImmediately $
          case publicationResult of
            Left _ -> ExitFailure 1
            Right _ -> ExitFailure 2
    closeFd readyWriter
    closeFd blockReader
    observedPoint <- requireLine readyReader
    closeFd readyReader
    assert
      (observedPoint == show requestedPoint)
      "the publication owner signals only after reaching the requested inode state"
    residueBeforeDeath <- listDirectory registryRoot
    assertPublicationResidue requestedPoint residueBeforeDeath
    signalProcess sigKILL publisherPid
    _ <- getProcessStatus True False publisherPid
    closeFd blockWriter
    liveRegistrations <-
      reconcileProcessIdentityRegistryForTest registryRoot
    observation <- observeProcessIdentityForTest registryRoot processId
    residueAfterReconcile <- listDirectory registryRoot
    assert
      ( null liveRegistrations
          && observation == Nothing
          && all (not . isIdentityRegistryEntry) residueAfterReconcile
      )
      "owner death before complete publication leaves only unlocked residue that reconciliation retires without accepting identity"

whenPoint ::
  PublicationTestPoint ->
  PublicationTestPoint ->
  IO () ->
  IO ()
whenPoint requestedPoint observedPoint action =
  if requestedPoint == observedPoint
    then action
    else pure ()

assertPublicationResidue :: PublicationTestPoint -> [FilePath] -> IO ()
assertPublicationResidue publicationPoint entries =
  case publicationPoint of
    PendingInodeLocked ->
      assert
        ( countEntries ".pending-v1." entries == 1
            && countEntries "process-v1." entries == 0
        )
        "death checkpoint before linking exposes one locked pending inode and no final token"
    FinalLinkInstalled ->
      assert
        ( countEntries ".pending-v1." entries == 1
            && countEntries "process-v1." entries == 1
        )
        "death checkpoint after linking exposes the locked pending and final names for one inode"

countEntries :: String -> [FilePath] -> Int
countEntries prefix =
  length . filter (prefix `isPrefixOf`)

isIdentityRegistryEntry :: FilePath -> Bool
isIdentityRegistryEntry entry =
  ".pending-v1." `isPrefixOf` entry
    || "process-v1." `isPrefixOf` entry

testCrossProcessDeath :: IO ()
testCrossProcessDeath = do
  (readyReader, readyWriter) <- createPipe
  (blockReader, blockWriter) <- createPipe
  childProcessId <-
    forkProcess $ do
      closeFd readyReader
      closeFd blockWriter
      childResult <-
        try @SomeException $ do
          dropInheritedProcessIdentity
          identity <- registerCurrentProcessIdentity
          processId <- getProcessID
          writeLine readyWriter (show processId)
          writeLine readyWriter (renderProcessBirthIdentity identity)
          closeFd readyWriter
          _ <- PosixByteString.fdRead blockReader 1
          pure ()
      closeFd blockReader
      exitImmediately $
        case childResult of
          Right () -> ExitSuccess
          Left _ -> ExitFailure 1
  closeFd readyWriter
  closeFd blockReader
  processIdLine <- requireLine readyReader
  identityLine <- requireLine readyReader
  closeFd readyReader
  observedProcessId <- requireProcessId processIdLine
  observedIdentity <-
    maybe
      (ioError (userError "child emitted an invalid process birth identity"))
      pure
      (parseProcessBirthIdentity identityLine)
  assert
    (observedProcessId == fromIntegral childProcessId)
    "the child publishes its exact PID before cross-process observation"
  liveObservation <- readProcessBirthIdentity observedProcessId
  assert
    (liveObservation == Just observedIdentity)
    "a separately registered process is observable while its kernel lock is live"
  signalProcess sigKILL childProcessId
  childStatus <- getProcessStatus True False childProcessId
  closeFd blockWriter
  assert
    (case childStatus of Just _ -> True; Nothing -> False)
    "the killed registry owner is synchronously reaped"
  deadObservation <- readProcessBirthIdentity observedProcessId
  assert
    (deadObservation == Nothing)
    "SIGKILL releases the registry lock and the next exact scan retires its token"

testInheritedStoppedChildRelease :: IO ()
testInheritedStoppedChildRelease = do
  (readyReader, readyWriter) <- createPipe
  (releaseReader, releaseWriter) <- createPipe
  ownerProcessId <-
    forkProcess $ do
      closeFd readyReader
      closeFd releaseWriter
      ownerResult <-
        try @SomeException $ do
          dropInheritedProcessIdentity
          ownerIdentity <- registerCurrentProcessIdentity
          ownerPid <- getProcessID
          stoppedChildPid <-
            forkProcess $ do
              dropInheritedProcessIdentity
              childPid <- getProcessID
              signalProcess sigSTOP childPid
              exitImmediately (ExitFailure 2)
          stoppedStatus <- getProcessStatus True True stoppedChildPid
          unless
            (case stoppedStatus of Just (Stopped _) -> True; _ -> False)
            (ioError (userError "inherited-lock child did not stop"))
          writeLine readyWriter (show ownerPid)
          writeLine readyWriter (renderProcessBirthIdentity ownerIdentity)
          writeLine readyWriter (show stoppedChildPid)
          closeFd readyWriter
          _ <- PosixByteString.fdRead releaseReader 1
          pure ()
      closeFd releaseReader
      exitImmediately $
        case ownerResult of
          Right () -> ExitSuccess
          Left _ -> ExitFailure 1
  closeFd readyWriter
  closeFd releaseReader
  ownerPidLine <- requireLine readyReader
  ownerIdentityLine <- requireLine readyReader
  stoppedChildPidLine <- requireLine readyReader
  closeFd readyReader
  observedOwnerPid <- requireProcessId ownerPidLine
  observedOwnerIdentity <-
    maybe
      (ioError (userError "owner emitted an invalid process birth identity"))
      pure
      (parseProcessBirthIdentity ownerIdentityLine)
  stoppedChildPid <- fromIntegral <$> requireProcessId stoppedChildPidLine
  assert
    (observedOwnerPid == fromIntegral ownerProcessId)
    "the fork owner publishes its exact identity after its child is stopped"
  liveObservation <- readProcessBirthIdentity observedOwnerPid
  assert
    (liveObservation == Just observedOwnerIdentity)
    "the owner registry token remains live before owner exit"
  _ <- PosixByteString.fdWrite releaseWriter (ByteString8.pack "x")
  closeFd releaseWriter
  ownerStatus <- getProcessStatus True False ownerProcessId
  assert
    (ownerStatus == Just (Exited ExitSuccess))
    "the registry owner exits only after its inherited-lock child is stopped"
  absentObservation <- readProcessBirthIdentity observedOwnerPid
  signalProcess sigKILL stoppedChildPid
  assert
    (absentObservation == Nothing)
    "a stopped fork child that dropped its inherited descriptor cannot extend the dead owner's registry lock"

concurrentObservations ::
  FilePath ->
  Integer ->
  Int ->
  IO [Maybe ProcessBirthIdentity]
concurrentObservations registryRoot processId count = do
  results <- replicateM count MVar.newEmptyMVar
  forM_ results $ \result -> do
    _ <-
      forkIO
        ( try @SomeException
            (observeProcessIdentityForTest registryRoot processId)
            >>= MVar.putMVar result
        )
    pure ()
  completed <-
    timeout
      10000000
      (mapM MVar.takeMVar results)
  case completed of
    Nothing ->
      ioError (userError "concurrent process-identity scans did not complete")
    Just observations ->
      traverse
        ( either
            (\failure -> ioError (userError ("concurrent scan failed: " <> show failure)))
            pure
        )
        observations

resetRegistry :: FilePath -> IO ()
resetRegistry registryRoot = do
  resetDirectory registryRoot
  prepareProcessIdentityRegistryForTest registryRoot

resetDirectory :: FilePath -> IO ()
resetDirectory path = do
  ignoreMissingPath (removePathForcibly path)
  createDirectoryIfMissing True (takeDirectory path)
  PosixDirectory.createDirectory path ownerModes
  setFileMode path ownerModes

createTestFile :: FilePath -> FileMode -> IO ()
createTestFile path mode = do
  descriptor <-
    openFd
      path
      WriteOnly
      defaultFileFlags
        { exclusive = True,
          nofollow = True,
          creat = Just mode,
          cloexec = True
        }
  closeFd descriptor

testIdentity :: Char -> Word64 -> ProcessBirthIdentity
testIdentity tokenCharacter startTime =
  ProcessBirthIdentity
    { processBirthBootIdentity = replicate 32 tokenCharacter,
      processBirthStartTime = startTime
    }

leftPad :: Int -> Char -> String -> String
leftPad width padding value =
  replicate (max 0 (width - length value)) padding <> value

writeLine :: Fd -> String -> IO ()
writeLine descriptor value =
  writeAll descriptor (ByteString8.pack (value <> "\n"))

writeAll :: Fd -> ByteString8.ByteString -> IO ()
writeAll descriptor bytes
  | ByteString8.null bytes = pure ()
  | otherwise = do
      written <- PosixByteString.fdWrite descriptor bytes
      let remaining = ByteString8.drop (fromIntegral written) bytes
      if written <= 0
        then ioError (userError "process-identity test pipe write made no progress")
        else writeAll descriptor remaining

requireLine :: Fd -> IO String
requireLine descriptor = do
  result <- timeout 5000000 (readBoundedLine descriptor 256)
  maybe
    (ioError (userError "timed out reading process-identity test evidence"))
    pure
    result

readBoundedLine :: Fd -> Int -> IO String
readBoundedLine descriptor maximumBytes =
  collect maximumBytes []
  where
    collect remaining characters
      | remaining <= 0 =
          ioError (userError "process-identity test evidence exceeded its bound")
      | otherwise = do
          chunk <- PosixByteString.fdRead descriptor 1
          case ByteString8.unpack chunk of
            "\n" -> pure (reverse characters)
            [character] -> collect (remaining - 1) (character : characters)
            "" -> ioError (userError "process-identity test evidence ended early")
            _ -> ioError (userError "process-identity test pipe returned an invalid chunk")

requireProcessId :: String -> IO Integer
requireProcessId value =
  case reads value of
    [(processId, "")]
      | processId > 0 -> pure processId
    _ -> ioError (userError ("invalid process ID evidence: " <> value))

ignoreMissingPath :: IO () -> IO ()
ignoreMissingPath action = do
  result <- try @IOException action
  case result of
    Right () -> pure ()
    Left failure
      | isDoesNotExistError failure -> pure ()
      | otherwise -> ioError failure

privateFileMode :: FileMode
privateFileMode =
  ownerReadMode .|. ownerWriteMode

#endif
