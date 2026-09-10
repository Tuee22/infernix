{-# LANGUAGE TypeApplications #-}

-- | Checked cleanup for pipes owned by the bounded subprocess kernel.
module Infernix.Cluster.Subprocess.Pipe
  ( closeOwnedPipe,
    requireOwnedPipeClosed,
    newOwnedDescriptorCloser,
  )
where

import Control.Concurrent.MVar (modifyMVar, newMVar)
import Control.Exception (IOException, SomeException, mask_, throwIO, try)
import Control.Monad (unless)
import System.IO (Handle, hClose, hIsClosed)
import System.Posix.IO (closeFd)
import System.Posix.Types (Fd)

-- A flush can report EPIPE after hClose has closed the handle. Such an error
-- is discharged only by a fresh positive closure observation.
closeOwnedPipe :: Handle -> IO ()
closeOwnedPipe handle = mask_ $ do
  result <- try @IOException (hClose handle)
  closed <- hIsClosed handle
  unless closed $
    case result of
      Left failure -> ioError failure
      Right () -> requireOwnedPipeClosed handle

requireOwnedPipeClosed :: Handle -> IO ()
requireOwnedPipeClosed handle = do
  closed <- hIsClosed handle
  unless closed (ioError (userError "bounded-command owned pipe remains open after cleanup"))

-- | Keep the result of the sole close attempt. Repeated cleanup must never
-- close a numeric descriptor that the process may already have reused.
newOwnedDescriptorCloser :: Fd -> IO (IO ())
newOwnedDescriptorCloser descriptor = do
  completion <- newMVar Nothing
  pure $ do
    result <- modifyMVar completion $ \previous ->
      case previous of
        Just observed -> pure (previous, observed)
        Nothing -> do
          observed <- try @SomeException (closeFd descriptor)
          pure (Just observed, observed)
    either throwIO pure result
