{-# LANGUAGE OverloadedStrings #-}

-- | Descriptor-relative verification of the producer's bounded model inventory.
module Infernix.Runtime.ModelCacheIdentity (verifyModelCacheIdentity) where

import Control.Exception (mask)
import Control.Monad (foldM, unless, when)
import Crypto.Hash.SHA256 qualified as SHA256
import Data.Aeson (FromJSON (parseJSON), withObject, (.:))
import Data.Aeson qualified as Aeson
import Data.Aeson.KeyMap qualified as KeyMap
import Data.ByteString qualified as ByteString
import Data.ByteString.Base16 qualified as Base16
import Data.Char (isControl)
import Data.List (sort)
import Data.Set qualified as Set
import Data.Text (Text)
import Data.Text qualified as Text
import Data.Text.Encoding qualified as Text
import Infernix.Error (bracketPreservingPrimary, finallyPreservingPrimary, onExceptionPreservingPrimary)
import System.IO.Error (catchIOError, isEOFError)
import System.Posix.Directory (closeDirStream, readDirStream, rewindDirStream)
import System.Posix.Directory.Fd (unsafeOpenDirStreamFd)
import System.Posix.Files (fileSize, getFdStatus, isDirectory, isRegularFile)
import System.Posix.IO (FdOption (CloseOnExec), OpenFileFlags (cloexec, directory, nofollow, nonBlock), OpenMode (ReadOnly), closeFd, defaultFileFlags, dup, openFd, openFdAt, setFdOption)
import System.Posix.IO.ByteString qualified as PosixByteString
import System.Posix.Types (Fd)

data Inventory = Inventory Int [InventoryEntry]

data InventoryEntry = InventoryEntry Text Integer Text

instance FromJSON Inventory where
  parseJSON = withObject "artifact inventory" $ \object -> do
    unless (KeyMap.size object == 2) (fail "unexpected inventory fields")
    Inventory <$> object .: "version" <*> object .: "files"

instance FromJSON InventoryEntry where
  parseJSON = withObject "artifact inventory entry" $ \object -> do
    unless (KeyMap.size object == 3) (fail "unexpected inventory entry fields")
    InventoryEntry <$> object .: "path" <*> object .: "size" <*> object .: "sha256"

-- | Verify exactly the engine's required keys and stream each opened regular
-- file into SHA-256. The held model directory is not a pin on its ancestors or
-- on the path an engine later opens.
verifyModelCacheIdentity :: FilePath -> [Text] -> IO (Either Text ())
verifyModelCacheIdentity root required =
  bracketPreservingPrimary
    (openFd root ReadOnly defaultFileFlags {nofollow = True, cloexec = True, directory = True})
    closeFd
    $ \rootFd -> do
      raw <- withRelativeFile rootFd [".infernix-artifact-inventory.json"] $ \fd -> readBounded fd (1024 * 1024 + 1)
      if ByteString.length raw > 1024 * 1024
        then pure (Left "artifact identity inventory exceeds its bound")
        else verifyDecoded rootFd (Aeson.eitherDecodeStrict' raw)
  where
    verifyDecoded rootFd decoded =
      case decoded of
        Left _ -> pure (Left "artifact identity inventory is malformed")
        Right (Inventory version entries) -> do
          let names = [name | InventoryEntry name _ _ <- entries]
          if version /= 1 || null entries || sort names /= sort required || not (all validEntry entries)
            then pure (Left "artifact identity inventory does not match the required files")
            else do
              verified <- verifyEntries rootFd entries
              case verified of
                Left reason -> pure (Left reason)
                Right () -> verifyCacheTree rootFd names
    validEntry (InventoryEntry name size digest) =
      validPath name && size >= 0 && Text.length digest == 64 && Text.all (`elem` ("0123456789abcdef" :: String)) digest

validPath :: Text -> Bool
validPath name =
  not (Text.null name)
    && Text.length name <= 4096
    && not (Text.any (\character -> isControl character || character == '\\') name)
    && all (\part -> not (Text.null part) && part /= "." && part /= "..") (Text.splitOn "/" name)
    && name `notElem` [".ready", ".infernix-artifact-inventory.json", ".infernix-native-snapshot-files"]

verifyEntries :: Fd -> [InventoryEntry] -> IO (Either Text ())
verifyEntries _ [] = pure (Right ())
verifyEntries rootFd (InventoryEntry name expectedSize expectedDigest : rest) = do
  result <- withRelativeFile rootFd (map Text.unpack (Text.splitOn "/" name)) $ \fd -> do
    status <- getFdStatus fd
    if not (isRegularFile status) || toInteger (fileSize status) /= expectedSize
      then pure False
      else do
        (actualSize, digest) <- hashFile fd 0 expectedSize SHA256.init
        pure (actualSize == expectedSize && Text.decodeUtf8 (Base16.encode (SHA256.finalize digest)) == expectedDigest)
  if result then verifyEntries rootFd rest else pure (Left ("cached artifact identity disagrees for " <> name))

-- The downloader's lock files and metadata are the only non-payload leaves
-- allowed. All directory traversal stays relative to opened descriptors.
verifyCacheTree :: Fd -> [Text] -> IO (Either Text ())
verifyCacheTree rootFd names = do
  let metadata = [".ready", ".infernix-native-snapshot-files", ".infernix-artifact-inventory.json"]
      locks = map (<> ".download.held") (names <> drop 1 metadata)
      allowed = Set.fromList (names <> metadata <> locks)
      directories = Set.fromList (concatMap parents (Set.toList allowed))
  (result, _) <- walk rootFd "" (0 :: Int) 0 allowed directories
  pure (if result then Right () else Left "cache contains an unlisted file or directory")
  where
    parents path =
      case Text.breakOnEnd "/" path of
        ("", _) -> []
        (prefix, _) -> let parent = Text.dropEnd 1 prefix in parent : parents parent
    walk fd prefix depth count allowed directories = do
      when (depth > 64) (ioError (userError "model cache identity tree exceeds depth bound"))
      children <- readDirectoryEntries fd (100000 - count)
      let countWithChildren = count + length children
      foldM (visit fd prefix depth allowed directories) (True, countWithChildren) children
    visit fd prefix depth allowed directories (valid, count) child =
      bracketPreservingPrimary
        (openFdAt (Just fd) child ReadOnly defaultFileFlags {nofollow = True, cloexec = True, nonBlock = True})
        closeFd
        $ \childFd -> do
          status <- getFdStatus childFd
          let relative = if Text.null prefix then Text.pack child else prefix <> "/" <> Text.pack child
          if isDirectory status
            then do
              (nested, nextCount) <- walk childFd relative (depth + 1) count allowed directories
              pure (valid && Set.member relative directories && nested, nextCount)
            else pure (valid && isRegularFile status && Set.member relative allowed, count)

readDirectoryEntries :: Fd -> Int -> IO [FilePath]
readDirectoryEntries descriptor limit = mask $ \restore -> do
  duplicate <- dup descriptor
  onExceptionPreservingPrimary (setFdOption duplicate CloseOnExec True) (closeFd duplicate)
  stream <- onExceptionPreservingPrimary (unsafeOpenDirStreamFd duplicate) (closeFd duplicate)
  finallyPreservingPrimary (restore (rewindDirStream stream >> collect stream limit [])) (closeDirStream stream)
  where
    collect stream remaining accumulated = do
      name <- readDirStream stream
      if null name
        then pure (reverse accumulated)
        else
          if name == "." || name == ".."
            then collect stream remaining accumulated
            else do
              when (remaining <= 0) (ioError (userError "model cache identity tree exceeds entry bound"))
              collect stream (remaining - 1) (name : accumulated)

withRelativeFile :: Fd -> [FilePath] -> (Fd -> IO a) -> IO a
withRelativeFile _ [] _ = ioError (userError "empty artifact path")
withRelativeFile parent [leaf] action =
  bracketPreservingPrimary (openFdAt (Just parent) leaf ReadOnly defaultFileFlags {nofollow = True, cloexec = True, nonBlock = True}) closeFd $ \fd -> do
    status <- getFdStatus fd
    unless (isRegularFile status) (ioError (userError "artifact inventory leaf is not a regular file"))
    action fd
withRelativeFile parent (component : rest) action =
  bracketPreservingPrimary (openFdAt (Just parent) component ReadOnly defaultFileFlags {nofollow = True, cloexec = True, directory = True}) closeFd $ \fd -> withRelativeFile fd rest action

readBounded :: Fd -> Int -> IO ByteString.ByteString
readBounded descriptor limit = go limit []
  where
    go remaining chunks
      | remaining <= 0 = pure (ByteString.concat (reverse chunks))
      | otherwise = do
          chunk <- readChunk descriptor (min remaining 65536)
          if ByteString.null chunk then pure (ByteString.concat (reverse chunks)) else go (remaining - ByteString.length chunk) (chunk : chunks)

hashFile :: Fd -> Integer -> Integer -> SHA256.Ctx -> IO (Integer, SHA256.Ctx)
hashFile descriptor size expected context = do
  chunk <- readChunk descriptor (fromInteger (min 65536 (expected - size + 1)))
  if ByteString.null chunk
    then pure (size, context)
    else do
      let next = SHA256.update context chunk
      let nextSize = size + toInteger (ByteString.length chunk)
      when (nextSize > expected) (ioError (userError "artifact identity file grew while hashing"))
      next `seq` hashFile descriptor nextSize expected next

readChunk :: Fd -> Int -> IO ByteString.ByteString
readChunk descriptor requested =
  catchIOError
    (PosixByteString.fdRead descriptor (fromIntegral requested))
    (\failure -> if isEOFError failure then pure ByteString.empty else ioError failure)
