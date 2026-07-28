module Main (main) where

import Data.Coerce (coerce)
import Infernix.Cluster (ClusterTeardownAuthority)

coerceAuthority ::
  ClusterTeardownAuthority sourceRegion ->
  ClusterTeardownAuthority targetRegion
coerceAuthority = coerce

main :: IO ()
main = pure ()
