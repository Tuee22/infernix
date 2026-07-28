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
  withKernelFileLock
    "generated Python bindings mutation"
    (toolsRoot </> ".infernix-generated-proto.lock")
    (action GeneratedBindingsMutationAuthority)
