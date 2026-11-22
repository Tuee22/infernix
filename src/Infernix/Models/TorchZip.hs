{-# LANGUAGE OverloadedStrings #-}

module Infernix.Models.TorchZip (readTorchZip) where

import Control.Monad (foldM, foldM_, unless, when)
import Data.Bits (shiftL, (.&.))
import Data.ByteString (ByteString)
import Data.ByteString qualified as BS
import Data.List (sortOn)
import Data.Map.Strict qualified as Map
import Data.Text (Text)
import Data.Text.Encoding qualified as Text
import Infernix.Models.TorchPickle (readTorchStorages)

data Entry = Entry {name :: ByteString, size :: Integer, offset :: Integer, flags :: Integer} deriving (Show)

readTorchZip :: Integer -> ByteString -> ByteString -> Either Text [(Text, Integer)]
readTorchZip total prefix suffix = do
  when (total <= 0 || toInteger (BS.length suffix) > total) (Left "invalid ZIP extent")
  let end = BS.length suffix
      base = total - toInteger end
  when (end < 22) (Left "truncated ZIP end")
  requireSignature suffix (end - 22) [80, 75, 5, 6]
  disk <- num suffix (end - 18) 2
  cdDisk <- num suffix (end - 16) 2
  diskCount <- num suffix (end - 14) 2
  count <- num suffix (end - 12) 2
  cdSize <- num suffix (end - 10) 4
  cdOffset <- num suffix (end - 6) 4
  commentLen <- num suffix (end - 2) 2
  unless (disk == 0 && cdDisk == 0 && diskCount == count && count > 0 && count < 65535 && cdSize < 4294967295 && cdOffset < 4294967295 && commentLen == 0) (Left "unsupported ZIP end record")
  let endOffset = total - 22
      cdEnd = cdOffset + cdSize
  if cdEnd == endOffset
    then pure ()
    else do
      unless (endOffset - cdEnd == 76 && cdEnd >= base) (Left "inconsistent ZIP directory extent")
      let zip64 = fromInteger (cdEnd - base)
      requireSignature suffix zip64 [80, 75, 6, 6]
      length64 <- num suffix (zip64 + 4) 8
      disk64 <- num suffix (zip64 + 16) 4
      cdDisk64 <- num suffix (zip64 + 20) 4
      diskCount64 <- num suffix (zip64 + 24) 8
      count64 <- num suffix (zip64 + 32) 8
      cdSize64 <- num suffix (zip64 + 40) 8
      cdOffset64 <- num suffix (zip64 + 48) 8
      requireSignature suffix (zip64 + 56) [80, 75, 6, 7]
      locatorDisk <- num suffix (zip64 + 60) 4
      locatorOffset <- num suffix (zip64 + 64) 8
      diskTotal <- num suffix (zip64 + 72) 4
      unless (length64 == 44 && disk64 == 0 && cdDisk64 == 0 && diskCount64 == count && count64 == count && cdSize64 == cdSize && cdOffset64 == cdOffset && locatorDisk == 0 && locatorOffset == cdEnd && diskTotal == 1) (Left "inconsistent ZIP64 directory")
  when (cdOffset < base || cdEnd > total || cdSize > 1048576) (Left "ZIP directory outside bounded suffix")
  let start = fromInteger (cdOffset - base)
      stop = fromInteger (cdEnd - base)
  (entries, pos) <- foldM (\(es, p) _ -> do (e, next) <- central suffix p; pure (e : es, next)) ([], start) [1 .. count]
  unless (pos == stop) (Left "ZIP directory count or size mismatch")
  let sorted = sortOn offset entries
      names = Map.fromList [(name e, e) | e <- entries]
  unless (length entries == Map.size names) (Left "duplicate ZIP entry")
  foldM_
    ( \previous e -> do
        when (offset e < previous) (Left "overlapping ZIP local entries")
        let minimumEnd = offset e + 30 + toInteger (BS.length (name e)) + size e + if flags e .&. 8 /= 0 then 12 else 0
        when (minimumEnd > cdOffset) (Left "ZIP entry crosses directory")
        pure minimumEnd
    )
    0
    sorted
  meta <- maybe (Left "pickle missing from ZIP") Right (Map.lookup "archive/data.pkl" names)
  unless (offset meta == 0 && size meta <= 1048576) (Left "unsupported pickle placement")
  requireSignature prefix 0 [80, 75, 3, 4]
  localFlags <- num prefix 6 2
  localMethod <- num prefix 8 2
  localNameLen <- num prefix 26 2
  localExtra <- num prefix 28 2
  localName <- slice prefix 30 (fromInteger localNameLen)
  unless (localFlags == flags meta && localMethod == 0 && localName == name meta) (Left "pickle local header disagrees with directory")
  let pickleStart = 30 + localNameLen + localExtra
  when (pickleStart + size meta > toInteger (BS.length prefix)) (Left "pickle outside bounded prefix")
  pickle <- slice prefix (fromInteger pickleStart) (fromInteger (size meta))
  storages <- readTorchStorages pickle
  let expected = Map.fromList [(BS.concat ["archive/data/", Text.encodeUtf8 k], n) | (k, n) <- Map.toList storages]
      stored = Map.fromList [(name e, size e) | e <- entries, BS.isPrefixOf "archive/data/" (name e)]
  unless (expected == stored && Map.size names == Map.size stored + 2 && Map.member "archive/version" names) (Left "ZIP storage declarations disagree")
  pure (Map.toList storages)

central :: ByteString -> Int -> Either Text (Entry, Int)
central bytes p = do
  requireSignature bytes p [80, 75, 1, 2]
  f <- num bytes (p + 8) 2
  method <- num bytes (p + 10) 2
  compressed <- num bytes (p + 20) 4
  uncompressed <- num bytes (p + 24) 4
  n <- num bytes (p + 28) 2
  x <- num bytes (p + 30) 2
  c <- num bytes (p + 32) 2
  disk <- num bytes (p + 34) 2
  off <- num bytes (p + 42) 4
  nm <- slice bytes (p + 46) (fromInteger n)
  unless (f .&. complementFlags == 0 && method == 0 && compressed == uncompressed && compressed < 4294967295 && off < 4294967295 && disk == 0 && n > 0) (Left "unsupported ZIP entry")
  let next = toInteger p + 46 + n + x + c
  when (next > toInteger (BS.length bytes)) (Left "truncated ZIP directory")
  pure (Entry nm uncompressed off f, fromInteger next)
  where
    complementFlags = 65535 - (2048 + 8)

slice :: ByteString -> Int -> Int -> Either Text ByteString
slice bytes p n
  | p < 0 || n < 0 || p > BS.length bytes - n = Left "truncated ZIP metadata"
  | otherwise = Right (BS.take n (BS.drop p bytes))

num :: ByteString -> Int -> Int -> Either Text Integer
num bytes p n = do
  s <- slice bytes p n
  pure (sum [toInteger b `shiftL` (8 * i) | (i, b) <- zip [0 ..] (BS.unpack s)])

requireSignature :: ByteString -> Int -> [Int] -> Either Text ()
requireSignature bytes p sig = do
  actual <- slice bytes p (length sig)
  unless (actual == BS.pack (map fromIntegral sig)) (Left "invalid ZIP signature")
