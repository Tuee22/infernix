module Main (main) where

import Data.Coerce (coerce)
import Infernix.Cluster (ClusterTeardownAuthority)

coerceAuthority ::
  ClusterTeardownAuthority owner sourceRegion ->
  ClusterTeardownAuthority owner targetRegion
coerceAuthority = coerce

main :: IO ()
main = pure ()
