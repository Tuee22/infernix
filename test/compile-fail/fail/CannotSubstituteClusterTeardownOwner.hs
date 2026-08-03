{-# LANGUAGE DataKinds #-}

module Main (main) where

import Infernix.Cluster (ClusterTeardownAuthority)
import Infernix.Types (ClusterOwner (..))

-- Sprint 6.45: a teardown authority minted for the harness must not be usable
-- where an operator-owned authority is required. The lifecycle region matches,
-- so only the promoted 'ClusterOwner' index can reject this.
substituteTeardownOwner ::
  ClusterTeardownAuthority 'HarnessOwned region ->
  ClusterTeardownAuthority 'OperatorOwned region
substituteTeardownOwner harnessAuthority = harnessAuthority

main :: IO ()
main = pure ()
