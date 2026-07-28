{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Engines.DownloadCacheLock.Internal
  ( DownloadCacheMutationAuthority,
    withDownloadCacheMutationLockInternal,
  )
where

import Control.Monad (unless)
import Infernix.Cluster.LifecycleLock (withKernelFileLock)
import System.FilePath ((</>))
import System.Posix.Files
  ( getSymbolicLinkStatus,
    isDirectory,
    isSymbolicLink,
  )

-- | Nominal evidence that the current continuation owns the fixed engine
-- download-cache lock. The constructor and raw lock operation stay private.
data DownloadCacheMutationAuthority d
  = DownloadCacheMutationAuthority

type role DownloadCacheMutationAuthority nominal

withDownloadCacheMutationLockInternal ::
  FilePath ->
  (forall d. DownloadCacheMutationAuthority d -> IO result) ->
  IO result
withDownloadCacheMutationLockInternal dataRoot action = do
  dataRootStatus <- getSymbolicLinkStatus dataRoot
  unless
    (isDirectory dataRootStatus && not (isSymbolicLink dataRootStatus))
    (ioError (userError "engine data root is not a real directory"))
  withKernelFileLock
    "engine download cache mutation"
    (dataRoot </> ".infernix-download-cache.lock")
    (action DownloadCacheMutationAuthority)
