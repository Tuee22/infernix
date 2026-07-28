module Infernix.Cluster.LifecycleLock
  ( withLifecycleFileLock,
    withKernelFileLock,
  )
where

import Infernix.Error (bracketPreservingPrimary)
import System.FileLock qualified as FileLock
import System.FilePath (normalise)

-- | Run an action only when a non-blocking, kernel-managed exclusive lock can
-- be acquired. The package lock token and its raw acquire/release operations
-- remain confined to this module.
withLifecycleFileLock :: FilePath -> IO a -> IO a
withLifecycleFileLock lockPath action =
  withKernelFileLock "cluster lifecycle" lockPath action

-- | Shared non-blocking, kernel-managed exclusion for internal state
-- transitions that need a persistent pathname but no residue-based ownership
-- protocol.
withKernelFileLock :: String -> FilePath -> IO a -> IO a
withKernelFileLock lockName lockPath action =
  bracketPreservingPrimary acquire FileLock.unlockFile (const action)
  where
    acquire = do
      lockResult <- FileLock.tryLockFile lockPath FileLock.Exclusive
      case lockResult of
        Just lockToken -> pure lockToken
        Nothing ->
          ioError
            ( userError
                ( lockName
                    <> " lock is already held: "
                    <> normalise lockPath
                )
            )
