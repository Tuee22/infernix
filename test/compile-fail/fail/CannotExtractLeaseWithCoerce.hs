module Main (main) where

import Data.Coerce (coerce)
import Infernix.Cluster (ClusterMutationLocked)
import Infernix.Evidence.Lease (Lease)

extract :: Lease s ClusterMutationLocked -> ClusterMutationLocked
extract = coerce

main :: IO ()
main = extract `seq` pure ()
