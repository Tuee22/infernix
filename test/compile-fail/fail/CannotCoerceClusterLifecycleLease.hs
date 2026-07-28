module Main (main) where

import Data.Coerce (coerce)
import Infernix.Cluster (ClusterMutationLocked)
import Infernix.Evidence.Lease (Lease)

data SourceRegion = SourceRegion

data TargetRegion = TargetRegion

coerceLifecycleLease ::
  Lease SourceRegion ClusterMutationLocked ->
  Lease TargetRegion ClusterMutationLocked
coerceLifecycleLease = coerce

main :: IO ()
main = pure ()
