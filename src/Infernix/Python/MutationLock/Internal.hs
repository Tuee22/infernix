{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RoleAnnotations #-}

module Infernix.Python.MutationLock.Internal
  ( PoetryProjectMutationAuthority,
    PoetryBootstrapMutationAuthority,
    GeneratedBindingsMutationAuthority,
    withPoetryProjectMutationLockInternal,
    withPoetryBootstrapMutationLockInternal,
    withGeneratedBindingsMutationLockInternal,
  )
where

import Infernix.Cluster.LifecycleLock (withKernelFileLock)
import System.Directory (createDirectoryIfMissing)
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
