{-# LANGUAGE RankNTypes #-}

module Main (main) where

import Infernix.Cluster
  ( ClusterMutationLocked,
    ClusterTeardownAuthority,
    clusterTeardownAuthorityRegionWitness,
    withClusterLifecycleLock,
  )
import Infernix.Config (Paths)
import Infernix.Evidence.Lease (Lease)

reuseAuthority ::
  Paths ->
  ClusterTeardownAuthority outerRegion ->
  IO ()
reuseAuthority paths authority =
  withClusterLifecycleLock paths $ \currentLock ->
    pure (clusterTeardownAuthorityRegionWitness currentLock authority)

main :: IO ()
main = pure ()
