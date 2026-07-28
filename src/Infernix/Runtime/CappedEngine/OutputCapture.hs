-- | Strict, bounded output capture shared by the capped-engine text and binary
-- protocols. This module owns no process handle; the caller supplies the
-- one-shot overflow action that terminates its exact process group.
module Infernix.Runtime.CappedEngine.OutputCapture
  ( BoundedCapture (..),
    readBoundedCapture,
  )
where

import Control.Monad (when)
import Data.ByteString (ByteString)
import Data.ByteString qualified as ByteString
import System.IO (Handle)

data BoundedCapture
  = BoundedCaptureCompleted !ByteString
  | BoundedCaptureExceeded !ByteString
  deriving (Eq, Show)

readBoundedCapture ::
  Int ->
  IO () ->
  Handle ->
  IO BoundedCapture
readBoundedCapture maximumBytes onOverflow inputHandle
  | maximumBytes <= 0 =
      ioError (userError "bounded capture requires a positive byte limit")
  | otherwise =
      go [] 0 False
  where
    go chunks retainedBytes overflowed = do
      chunk <- ByteString.hGetSome inputHandle captureChunkBytes
      if ByteString.null chunk
        then
          pure
            ( if overflowed
                then BoundedCaptureExceeded retainedOutput
                else BoundedCaptureCompleted retainedOutput
            )
        else
          if overflowed
            then go chunks retainedBytes True
            else do
              let availableBytes = maximumBytes - retainedBytes
                  retainedChunk = ByteString.take availableBytes chunk
                  nextChunks =
                    if ByteString.null retainedChunk
                      then chunks
                      else retainedChunk : chunks
                  nextRetainedBytes =
                    retainedBytes + ByteString.length retainedChunk
                  exceeded =
                    ByteString.length chunk > availableBytes
              when exceeded onOverflow
              go nextChunks nextRetainedBytes exceeded
      where
        retainedOutput = ByteString.concat (reverse chunks)

captureChunkBytes :: Int
captureChunkBytes = 32768
