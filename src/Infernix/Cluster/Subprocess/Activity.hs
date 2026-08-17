{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications #-}

-- | Durable activity publication for the bounded-command kernel.
--
-- The publication plan is opaque. Its only interpreter performs the complete
-- write, file-sync, atomic rename, and directory-sync sequence, so protocol
-- code cannot replace durable publication with an arbitrary callback.
module Infernix.Cluster.Subprocess.Activity
  ( ActivityPublication,
    ActivityDurable,
    ActivityPublicationTestHook,
    planActivityPrewriteTestHook,
    planActivityPublicationTestHook,
    planActivityPublication,
    publishActivityPublication,
  )
where

import Control.Concurrent (yield)
import Control.Exception (IOException, mask, try)
import Control.Monad (unless, when)
import Data.Bits ((.|.))
import Data.ByteString qualified as ByteString
import Data.ByteString.Char8 qualified as ByteString8
import Data.List (isPrefixOf)
import GHC.IO.Exception (IOErrorType (EOF, Interrupted, ResourceExhausted))
import Infernix.Error
  ( finallyPreservingPrimary,
    onExceptionPreservingPrimary,
  )
import System.Directory
  ( createDirectoryIfMissing,
    doesFileExist,
    renameFile,
  )
import System.FilePath (isValid, takeDirectory, takeFileName, (</>))
import System.IO
  ( BufferMode (NoBuffering),
    Handle,
    hClose,
    hFlush,
    hIsClosed,
    hSetBinaryMode,
    hSetBuffering,
  )
import System.IO.Error (ioeGetErrorType)
import System.Posix.Files
  ( getSymbolicLinkStatus,
    isDirectory,
    ownerModes,
    ownerReadMode,
    ownerWriteMode,
    setFileMode,
  )
import System.Posix.IO
  ( OpenFileFlags (cloexec, creat, exclusive, nofollow, nonBlock),
    OpenMode (ReadOnly, WriteOnly),
    closeFd,
    defaultFileFlags,
    fdToHandle,
    handleToFd,
    openFd,
  )
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Types (FileMode)
import System.Posix.Unistd (fileSynchronise)

-- | A complete, opaque durable-publication plan.
data ActivityPublication = ActivityPublication
  { publicationRoot :: !FilePath,
    publicationPath :: !FilePath,
    publicationIncomingName :: !FilePath,
    publicationContents :: !ByteString.ByteString,
    publicationDurabilityMarkers :: !(Maybe (FilePath, FilePath)),
    publicationTestHooks :: ![ActivityPublicationTestHook]
  }

-- | Evidence minted only after the complete publication sequence returns.
data ActivityDurable = ActivityDurable

data ActivityPublicationHookPhase
  = ActivityPrewrite
  | ActivityPostwrite
  deriving (Eq)

-- | Deterministic adversarial coordination at one package-selected
-- publication phase. The phase constructor is intentionally hidden.
data ActivityPublicationTestHook = ActivityPublicationTestHook
  { testHookPhase :: !ActivityPublicationHookPhase,
    testHookReadyPath :: !FilePath,
    testHookReleaseFifo :: !FilePath
  }

-- | Coordinate immediately after the incoming directory entry is durable and
-- before any activity payload is written.
planActivityPrewriteTestHook ::
  FilePath ->
  FilePath ->
  ActivityPublicationTestHook
planActivityPrewriteTestHook =
  ActivityPublicationTestHook ActivityPrewrite

-- | Coordinate after the complete payload is file-synchronized and before
-- the incoming entry is renamed into place.
planActivityPublicationTestHook ::
  FilePath ->
  FilePath ->
  ActivityPublicationTestHook
planActivityPublicationTestHook =
  ActivityPublicationTestHook ActivityPostwrite

-- | Plan one publication. The final path must be a direct child of the
-- activity root. The incoming name must be a direct basename beginning with
-- @.incoming-activity-v3.@, @.incoming-activity-v4.i@, or
-- @.incoming-activity-v5.@; the interpreter
-- rechecks both path constraints.
planActivityPublication ::
  FilePath ->
  FilePath ->
  FilePath ->
  ByteString.ByteString ->
  Maybe (FilePath, FilePath) ->
  [ActivityPublicationTestHook] ->
  ActivityPublication
planActivityPublication
  activityRoot
  activityPath
  incomingName
  contents
  durabilityMarkers
  testHooks =
    ActivityPublication
      { publicationRoot = activityRoot,
        publicationPath = activityPath,
        publicationIncomingName = incomingName,
        publicationContents = contents,
        publicationDurabilityMarkers = durabilityMarkers,
        publicationTestHooks = testHooks
      }

-- | Execute the only durability transition for an activity publication.
publishActivityPublication :: ActivityPublication -> IO ActivityDurable
publishActivityPublication publication = mask $ \restore -> do
  let activityRoot = publicationRoot publication
      activityPath = publicationPath publication
      incomingName = publicationIncomingName publication
      incomingPath = activityRoot </> incomingName
  unless (validDirectChild activityRoot activityPath) $
    ioError
      (userError "bounded-command activity lease path is outside its activity root")
  unless (validIncomingName incomingName) $
    ioError
      (userError "bounded-command incoming activity name is not a valid direct basename")
  ensureActivityRoot activityRoot
  synchroniseDirectory (takeDirectory activityRoot)
  activityAlreadyPublished <- doesFileExist activityPath
  when activityAlreadyPublished $
    ioError
      ( userError
          ( "bounded-command activity lease already exists: "
              <> activityPath
          )
      )
  temporary <- createIncomingActivity incomingPath
  onExceptionPreservingPrimary
    ( restore $ do
        let (temporaryPath, handle) = temporary
        synchroniseDirectory activityRoot
        runPublicationTestHooks
          ActivityPrewrite
          temporaryPath
          (publicationTestHooks publication)
        ByteString.hPut
          handle
          (publicationContents publication)
        hFlush handle
        setFileMode temporaryPath activityLeaseMode
        descriptor <- handleToFd handle
        finallyPreservingPrimary
          (fileSynchronise descriptor)
          (closeFd descriptor)
        mapM_
          (`ByteString.writeFile` "file-synchronized\n")
          (fst <$> publicationDurabilityMarkers publication)
        runPublicationTestHooks
          ActivityPostwrite
          temporaryPath
          (publicationTestHooks publication)
        renameFile temporaryPath activityPath
        synchroniseDirectory activityRoot
        mapM_
          (`ByteString.writeFile` "directory-synchronized\n")
          (snd <$> publicationDurabilityMarkers publication)
    )
    -- The incoming filename carries exact recovery identities. Close its
    -- descriptor here, but let the outer kernel retire the entry only after it
    -- has proved every recorded process group absent.
    (closeTemporaryActivityHandle temporary)
  pure ActivityDurable

validIncomingName :: FilePath -> Bool
validIncomingName incomingName =
  validBasename incomingName
    && ( ".incoming-activity-v3." `isPrefixOf` incomingName
           || ".incoming-activity-v4.i" `isPrefixOf` incomingName
           || ".incoming-activity-v5." `isPrefixOf` incomingName
       )

validDirectChild :: FilePath -> FilePath -> Bool
validDirectChild root path =
  isValid path
    && takeDirectory path == root
    && validBasename (takeFileName path)

validBasename :: FilePath -> Bool
validBasename name =
  isValid name
    && takeFileName name == name
    && name /= "."
    && name /= ".."

createIncomingActivity :: FilePath -> IO (FilePath, Handle)
createIncomingActivity incomingPath = mask $ \_ -> do
  descriptor <-
    openFd
      incomingPath
      WriteOnly
      defaultFileFlags
        { exclusive = True,
          nofollow = True,
          creat = Just activityLeaseMode,
          cloexec = True
        }
  handle <-
    onExceptionPreservingPrimary
      (fdToHandle descriptor)
      (closeFd descriptor)
  onExceptionPreservingPrimary
    ( do
        hSetBinaryMode handle True
        hSetBuffering handle NoBuffering
        pure (incomingPath, handle)
    )
    (closeTemporaryActivityHandle (incomingPath, handle))

runPublicationTestHooks ::
  ActivityPublicationHookPhase ->
  FilePath ->
  [ActivityPublicationTestHook] ->
  IO ()
runPublicationTestHooks phase temporaryPath =
  mapM_ $ \testHook ->
    when (testHookPhase testHook == phase) $
      runPublicationTestHook temporaryPath testHook

runPublicationTestHook ::
  FilePath ->
  ActivityPublicationTestHook ->
  IO ()
runPublicationTestHook temporaryPath testHook = do
  release <-
    readNamedPipePayloadAfterReady
      temporaryPath
      testHook
  unless (release == "release\n") $
    ioError
      (userError "bounded-command activity publication release was invalid")

readNamedPipePayloadAfterReady ::
  FilePath ->
  ActivityPublicationTestHook ->
  IO ByteString.ByteString
readNamedPipePayloadAfterReady temporaryPath testHook = mask $ \restore -> do
  descriptor <-
    restore
      ( openFd
          (testHookReleaseFifo testHook)
          ReadOnly
          defaultFileFlags
            { nofollow = True,
              nonBlock = True,
              cloexec = True
            }
      )
  finallyPreservingPrimary
    ( do
        ByteString.writeFile
          (testHookReadyPath testHook)
          (ByteString8.pack (temporaryPath <> "\n"))
        restore (readBounded descriptor 0 [] False)
    )
    (closeFd descriptor)
  where
    maximumBytes = 64

    readBounded descriptor bytesRead chunks receivedAny = do
      result <-
        try @IOException
          ( PosixByteString.fdRead
              descriptor
              (fromIntegral (maximumBytes + 1 - bytesRead))
          )
      case result of
        Left failure
          | retryableDescriptorError failure ->
              yield >> readBounded descriptor bytesRead chunks receivedAny
          | ioeGetErrorType failure == EOF ->
              handleEmpty descriptor bytesRead chunks receivedAny
          | otherwise -> ioError failure
        Right contents
          | ByteString.null contents ->
              handleEmpty descriptor bytesRead chunks receivedAny
          | ByteString.length contents > maximumBytes - bytesRead ->
              ioError
                (userError "bounded-command activity release exceeds its size limit")
          | otherwise ->
              readBounded
                descriptor
                (bytesRead + ByteString.length contents)
                (contents : chunks)
                True

    handleEmpty descriptor bytesRead chunks receivedAny
      | receivedAny = pure (ByteString.concat (reverse chunks))
      | otherwise = yield >> readBounded descriptor bytesRead chunks False

    retryableDescriptorError failure =
      ioeGetErrorType failure `elem` [Interrupted, ResourceExhausted]

activityLeaseMode :: FileMode
activityLeaseMode =
  ownerReadMode .|. ownerWriteMode

ensureActivityRoot :: FilePath -> IO ()
ensureActivityRoot activityRoot = do
  createDirectoryIfMissing True activityRoot
  status <- getSymbolicLinkStatus activityRoot
  if isDirectory status
    then setFileMode activityRoot ownerModes
    else
      ioError
        ( userError
            ( "bounded-command activity root is not a directory: "
                <> activityRoot
            )
        )

synchroniseDirectory :: FilePath -> IO ()
synchroniseDirectory directoryPath = mask $ \restore -> do
  descriptor <- openFd directoryPath ReadOnly defaultFileFlags
  finallyPreservingPrimary
    (restore (fileSynchronise descriptor))
    (closeFd descriptor)

closeTemporaryActivityHandle :: (FilePath, Handle) -> IO ()
closeTemporaryActivityHandle (_, handle) = do
  closed <- hIsClosed handle
  unless closed (hClose handle)
