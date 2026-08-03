{-# LANGUAGE RankNTypes #-}

module Main (main) where

import Infernix.Cluster
  ( ClusterMutationLocked,
    ClusterTeardownAuthority,
    withClusterLifecycleLock,
  )
import Infernix.Config (Paths)
import Infernix.Evidence.Lease (Lease)

escapeAuthority ::
  Paths ->
  (forall s. Lease s ClusterMutationLocked -> IO (ClusterTeardownAuthority owner s)) ->
  IO (ClusterTeardownAuthority owner ())
escapeAuthority =
  withClusterLifecycleLock

main :: IO ()
main = pure ()
