{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Python.MutationLock.Internal
  ( PoetryProjectMutationAuthority,
    PoetryProjectReadAuthority,
    PoetryBootstrapMutationAuthority,
    GeneratedBindingsMutationAuthority,
    withPoetryProjectMutationLockInternal,
    withPoetryProjectReadLockInternal,
    withPoetryBootstrapMutationLockInternal,
    withGeneratedBindingsMutationLockInternal,
  )
where

import Infernix.Cluster.LifecycleLock (withKernelFileLock)
import Infernix.Error (bracketPreservingPrimary)
import System.Directory (createDirectoryIfMissing)
import System.FileLock qualified as FileLock
import System.FilePath ((</>))

data PoetryProjectMutationAuthority p
  = PoetryProjectMutationAuthority

type role PoetryProjectMutationAuthority nominal

withPoetryProjectMutationLockInternal ::
  FilePath ->
  (forall p. PoetryProjectMutationAuthority p -> IO a) ->
  IO a
withPoetryProjectMutationLockInternal projectDirectory action =
  withKernelFileLock
    "Poetry project mutation"
    (projectDirectory </> ".infernix-poetry-install.lock")
    (action PoetryProjectMutationAuthority)

-- | Shared runtime custody over the same kernel lock that excludes Poetry
-- project writers. The nominal authority can exist only inside this rank-2
-- region; a prepared-environment reader wraps it only after validating the
-- exact marker and interpreter while the lock remains held.
data PoetryProjectReadAuthority r
  = PoetryProjectReadAuthority

type role PoetryProjectReadAuthority nominal

withPoetryProjectReadLockInternal ::
  FilePath ->
  (forall r. PoetryProjectReadAuthority r -> IO a) ->
  IO a
withPoetryProjectReadLockInternal projectDirectory action =
  bracketPreservingPrimary acquire FileLock.unlockFile $ \_ ->
    action PoetryProjectReadAuthority
  where
    lockPath = projectDirectory </> ".infernix-poetry-install.lock"
    acquire = do
      lockResult <- FileLock.tryLockFile lockPath FileLock.Shared
      case lockResult of
        Just lockToken -> pure lockToken
        Nothing ->
          ioError
            ( userError
                ( "Poetry project read lock is excluded by an active writer: "
                    <> lockPath
                )
            )

data PoetryBootstrapMutationAuthority b
  = PoetryBootstrapMutationAuthority

type role PoetryBootstrapMutationAuthority nominal

withPoetryBootstrapMutationLockInternal ::
  FilePath ->
  (forall b. PoetryBootstrapMutationAuthority b -> IO a) ->
  IO a
withPoetryBootstrapMutationLockInternal homeDirectory action =
  withKernelFileLock
    "Poetry bootstrap mutation"
    (homeDirectory </> ".infernix-poetry-bootstrap.lock")
    (action PoetryBootstrapMutationAuthority)

data GeneratedBindingsMutationAuthority g
  = GeneratedBindingsMutationAuthority

type role GeneratedBindingsMutationAuthority nominal

withGeneratedBindingsMutationLockInternal ::
  FilePath ->
  (forall g. GeneratedBindingsMutationAuthority g -> IO a) ->
  IO a
withGeneratedBindingsMutationLockInternal repositoryRoot action = do
  let toolsRoot = repositoryRoot </> "tools"
  -- The lock leaf is created on demand by 'tryLockFile', but its parent is
  -- untracked and is otherwise created only later inside the session, so a
  -- fresh checkout would fail ENOENT before the body ran. Own the parent here,
  -- exactly as the engine materialization lock owns its engines root.
  createDirectoryIfMissing True toolsRoot
  withKernelFileLock
    "generated Python bindings mutation"
    (toolsRoot </> ".infernix-generated-proto.lock")
    (action GeneratedBindingsMutationAuthority)
