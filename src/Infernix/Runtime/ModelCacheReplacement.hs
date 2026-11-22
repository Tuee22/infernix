{-# LANGUAGE OverloadedStrings #-}

-- | Package-internal model-cache replacement. Callers hold the model's
-- exclusive cache-root and runtime leases throughout every operation here.
module Infernix.Runtime.ModelCacheReplacement
  ( cacheReplacementPending,
    recoverCacheReplacement,
    replaceCacheGeneration,
    replaceCacheGenerationWithHookForTest,
  )
where

import Control.Exception (mask)
import Control.Monad (foldM, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.ByteString.Char8 qualified as ByteString8
import Data.Char (isAsciiLower, isDigit)
import Data.Maybe (isJust)
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Infernix.Error (bracketPreservingPrimary, finallyPreservingPrimary, onExceptionPreservingPrimary)
import System.Directory (createDirectory, createDirectoryIfMissing, removeDirectory, removePathForcibly, renameDirectory)
import System.FilePath ((</>))
import System.IO.Error (catchIOError, isDoesNotExistError)
import System.Posix.Directory (closeDirStream, readDirStream, rewindDirStream)
import System.Posix.Directory.Fd (unsafeOpenDirStreamFd)
import System.Posix.Files (FileStatus, deviceID, fileID, fileSize, getFdStatus, getSymbolicLinkStatus, isDirectory, isRegularFile)
import System.Posix.IO (FdOption (CloseOnExec), OpenFileFlags (cloexec, creat, directory, exclusive, nofollow, nonBlock), OpenMode (ReadOnly, WriteOnly), closeFd, defaultFileFlags, dup, openFd, openFdAt, setFdOption)
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Types (Fd)
import System.Posix.Unistd (fileSynchronise)
import Text.Read (readMaybe)

data ReplacementPaths = ReplacementPaths
  { replacementRoot :: FilePath,
    replacementTransaction :: FilePath,
    replacementStageRoot :: FilePath,
    replacementCandidate :: FilePath,
    replacementPrevious :: FilePath,
    replacementModel :: FilePath,
    replacementMarker :: FilePath,
    replacementIntent :: FilePath
  }

replacementPaths :: FilePath -> Text -> IO ReplacementPaths
replacementPaths root modelIdValue = do
  unless (validModelId modelIdValue) $
    ioError (userError "model cache replacement requires a canonical model identifier")
  let transactionParent = root </> ".infernix-cache-rebuild"
      transaction = transactionParent </> ByteString8.unpack (Base16.encode (SHA256.hash (Text.encodeUtf8 modelIdValue)))
      stageRoot = transaction </> "stage"
  pure
    ReplacementPaths
      { replacementRoot = root,
        replacementTransaction = transaction,
        replacementStageRoot = stageRoot,
        replacementCandidate = stageRoot </> Text.unpack modelIdValue,
        replacementPrevious = transaction </> "previous",
        replacementModel = root </> Text.unpack modelIdValue,
        replacementMarker = transaction </> "owner",
        replacementIntent = transaction </> "candidate-identity"
      }

validModelId :: Text -> Bool
validModelId value =
  case Text.uncons value of
    Nothing -> False
    Just (firstCharacter, rest) -> alphaNumeric firstCharacter && go False rest
  where
    alphaNumeric character = isAsciiLower character || (isDigit character && character <= '9')
    go previousSeparator remaining =
      case Text.uncons remaining of
        Nothing -> not previousSeparator
        Just (character, tailValue)
          | alphaNumeric character -> go False tailValue
          | character `elem` ("._-" :: String) && not previousSeparator -> go True tailValue
          | otherwise -> False

cacheReplacementPending :: FilePath -> Text -> IO Bool
cacheReplacementPending root modelIdValue = do
  paths <- replacementPaths root modelIdValue
  parentExists <- replacementParentExists paths
  if parentExists
    then isJust <$> statusMaybe (replacementTransaction paths)
    else pure False

-- | Recover conservatively. An unrecognised transaction or an unexpected
-- current generation is refused without deleting either generation.
recoverCacheReplacement :: FilePath -> Text -> IO ()
recoverCacheReplacement root modelIdValue = do
  paths <- replacementPaths root modelIdValue
  parentExists <- replacementParentExists paths
  maybeTransaction <- if parentExists then statusMaybe (replacementTransaction paths) else pure Nothing
  case maybeTransaction of
    Nothing -> pure ()
    Just transactionStatus -> do
      unless (isDirectory transactionStatus) $
        ioError (userError "model cache replacement path is not a directory")
      marker <- readSmallFileMaybe (replacementMarker paths)
      case marker of
        Nothing -> do
          entries <- transactionEntries paths
          if null entries
            then do
              removeDirectory (replacementTransaction paths)
              syncDirectory (root </> ".infernix-cache-rebuild")
            else ioError (userError "model cache replacement has no ownership marker")
        Just markerBytes -> do
          unless (markerBytes == Text.encodeUtf8 modelIdValue) $
            ioError (userError "model cache replacement ownership marker disagrees")
          entries <- transactionEntries paths
          unless (all (`elem` ["owner", "candidate-identity", "stage", "previous"]) entries) $
            ioError (userError "model cache replacement contains unrecognised entries")
          previous <- directoryExists (replacementPrevious paths)
          current <- directoryExists (replacementModel paths)
          case (previous, current) of
            (True, False) -> do
              renameDirectory (replacementPrevious paths) (replacementModel paths)
              syncDirectory (replacementRoot paths)
              syncDirectory (replacementTransaction paths)
            (True, True) -> do
              expected <- readIdentity (replacementIntent paths)
              actual <- directoryIdentity (replacementModel paths)
              unless (actual == expected) $
                ioError (userError "model cache replacement current generation has unexpected identity")
            _ -> pure ()
          removePathForcibly (replacementTransaction paths)
          syncDirectory (replacementRoot paths </> ".infernix-cache-rebuild")

replaceCacheGeneration :: FilePath -> Text -> Integer -> (FilePath -> IO (Either e ())) -> IO (Either e ())
replaceCacheGeneration root modelIdValue quota buildCandidate =
  replaceCacheGenerationWithHookForTest root modelIdValue quota buildCandidate (pure ()) (pure ())

-- The hook is package-private and is used only by fault-injection tests after
-- the prior generation moves. Production always supplies the no-op above.
replaceCacheGenerationWithHookForTest :: FilePath -> Text -> Integer -> (FilePath -> IO (Either e ())) -> IO () -> IO () -> IO (Either e ())
replaceCacheGenerationWithHookForTest root modelIdValue quota buildCandidate afterPrevious afterPromotion =
  mask $ \restore -> do
    when (quota <= 0) (ioError (userError "model cache replacement quota must be positive"))
    paths <- replacementPaths root modelIdValue
    createDirectoryIfMissing True root
    requireDirectory root
    createDirectoryIfMissing True (root </> ".infernix-cache-rebuild")
    requireDirectory (root </> ".infernix-cache-rebuild")
    syncDirectory root
    recoverCacheReplacement root modelIdValue
    onExceptionPreservingPrimary
      ( do
          createDirectory (replacementTransaction paths)
          writeExclusive (replacementMarker paths) (Text.encodeUtf8 modelIdValue)
          syncDirectory (replacementTransaction paths)
          syncDirectory (root </> ".infernix-cache-rebuild")
          createDirectory (replacementStageRoot paths)
          built <- restore (buildCandidate (replacementStageRoot paths))
          case built of
            Left refusal -> do
              recoverCacheReplacement root modelIdValue
              pure (Left refusal)
            Right () -> do
              restore (syncCandidate (replacementCandidate paths) quota)
              syncDirectory (replacementStageRoot paths)
              identity <- directoryIdentity (replacementCandidate paths)
              writeExclusive (replacementIntent paths) (ByteString8.pack (show identity))
              syncDirectory (replacementTransaction paths)
              present <- directoryExists (replacementModel paths)
              when present $ do
                renameDirectory (replacementModel paths) (replacementPrevious paths)
                syncDirectory (replacementTransaction paths)
                syncDirectory root
                restore afterPrevious
              renameDirectory (replacementCandidate paths) (replacementModel paths)
              syncDirectory root
              syncDirectory (replacementStageRoot paths)
              restore afterPromotion
              recoverCacheReplacement root modelIdValue
              pure (Right ())
      )
      (recoverCacheReplacement root modelIdValue)

replacementParentExists :: ReplacementPaths -> IO Bool
replacementParentExists paths = do
  rootExists <- directoryExists (replacementRoot paths)
  if rootExists
    then directoryExists (replacementRoot paths </> ".infernix-cache-rebuild")
    else pure False

requireDirectory :: FilePath -> IO ()
requireDirectory path = do
  present <- directoryExists path
  unless present (ioError (userError ("model cache directory is absent: " <> path)))

transactionEntries :: ReplacementPaths -> IO [FilePath]
transactionEntries paths =
  bracketPreservingPrimary
    (openFd (replacementTransaction paths) ReadOnly defaultFileFlags {nofollow = True, cloexec = True, directory = True})
    closeFd
    (`readEntries` 4)

statusMaybe :: FilePath -> IO (Maybe FileStatus)
statusMaybe path = catchIOError (Just <$> getSymbolicLinkStatus path) classify
  where
    classify failure
      | isDoesNotExistError failure = pure Nothing
      | otherwise = ioError failure

directoryExists :: FilePath -> IO Bool
directoryExists path = do
  status <- statusMaybe path
  case status of
    Nothing -> pure False
    Just value
      | isDirectory value -> pure True
      | otherwise -> ioError (userError ("model cache generation is not a directory: " <> path))

directoryIdentity :: FilePath -> IO (Integer, Integer)
directoryIdentity path = do
  status <- getSymbolicLinkStatus path
  unless (isDirectory status) (ioError (userError "model cache candidate is not a directory"))
  pure (toInteger (deviceID status), toInteger (fileID status))

readIdentity :: FilePath -> IO (Integer, Integer)
readIdentity path = do
  payload <- readSmallFileMaybe path
  maybe
    (ioError (userError "model cache replacement lacks a valid candidate identity"))
    pure
    (payload >>= readMaybe . ByteString8.unpack)

readSmallFileMaybe :: FilePath -> IO (Maybe ByteString.ByteString)
readSmallFileMaybe path = do
  status <- statusMaybe path
  case status of
    Nothing -> pure Nothing
    Just value -> do
      unless (isRegularFile value && fileSize value <= 1024) $
        ioError (userError "model cache replacement metadata is not a bounded regular file")
      Just
        <$> bracketPreservingPrimary
          (openFd path ReadOnly defaultFileFlags {nofollow = True, cloexec = True})
          closeFd
          (`PosixByteString.fdRead` 1025)

writeExclusive :: FilePath -> ByteString.ByteString -> IO ()
writeExclusive path payload =
  bracketPreservingPrimary
    (openFd path WriteOnly defaultFileFlags {nofollow = True, cloexec = True, exclusive = True, creat = Just 0o600})
    closeFd
    $ \fd -> do
      written <- PosixByteString.fdWrite fd payload
      unless (toInteger written == toInteger (ByteString.length payload)) $
        ioError (userError "model cache replacement metadata write was incomplete")
      fileSynchronise fd

syncDirectory :: FilePath -> IO ()
syncDirectory path =
  bracketPreservingPrimary
    (openFd path ReadOnly defaultFileFlags {nofollow = True, cloexec = True, directory = True})
    closeFd
    fileSynchronise

syncCandidate :: FilePath -> Integer -> IO ()
syncCandidate path quota =
  bracketPreservingPrimary
    (openFd path ReadOnly defaultFileFlags {nofollow = True, cloexec = True, directory = True})
    closeFd
    $ \fd -> do
      _ <- syncTree fd quota 0 (0, 0)
      pure ()

syncTree :: Fd -> Integer -> Int -> (Int, Integer) -> IO (Int, Integer)
syncTree parent quota depth totals = do
  when (depth > 64) (ioError (userError "model cache candidate exceeds directory depth bound"))
  names <- readEntries parent (100000 - fst totals)
  let reserved = (fst totals + length names, snd totals)
  final <- foldM (syncChild parent quota depth) reserved names
  fileSynchronise parent
  pure final

syncChild :: Fd -> Integer -> Int -> (Int, Integer) -> FilePath -> IO (Int, Integer)
syncChild parent quota depth (count, bytes) name =
  bracketPreservingPrimary
    (openFdAt (Just parent) name ReadOnly defaultFileFlags {nofollow = True, cloexec = True, nonBlock = True})
    closeFd
    $ \fd -> do
      status <- getFdStatus fd
      if isDirectory status
        then syncTree fd quota (depth + 1) (count, bytes)
        else
          if isRegularFile status
            then do
              let nextBytes = bytes + toInteger (fileSize status)
              when (nextBytes > quota) (ioError (userError "model cache candidate exceeds its quota"))
              fileSynchronise fd
              pure (count, nextBytes)
            else ioError (userError "model cache candidate contains a non-regular entry")

readEntries :: Fd -> Int -> IO [FilePath]
readEntries descriptor limit = mask $ \restore -> do
  duplicate <- dup descriptor
  onExceptionPreservingPrimary (setFdOption duplicate CloseOnExec True) (closeFd duplicate)
  stream <- onExceptionPreservingPrimary (unsafeOpenDirStreamFd duplicate) (closeFd duplicate)
  finallyPreservingPrimary
    (restore (rewindDirStream stream >> collect stream limit []))
    (closeDirStream stream)
  where
    collect stream remaining accumulated = do
      name <- readDirStream stream
      if null name
        then pure (reverse accumulated)
        else
          if name == "." || name == ".."
            then collect stream remaining accumulated
            else do
              when (remaining <= 0) (ioError (userError "model cache candidate exceeds entry bound"))
              collect stream (remaining - 1) (name : accumulated)
