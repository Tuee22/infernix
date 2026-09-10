module Main (main) where

import Infernix.Cluster (ClusterMutationLocked, ClusterTeardownAuthority, clusterTeardownAuthorityRegionWitness)
import Infernix.Evidence.Lease (Lease)

reuseAuthority :: Lease current ClusterMutationLocked -> ClusterTeardownAuthority owner previous -> ()
reuseAuthority = clusterTeardownAuthorityRegionWitness

main :: IO ()
main = reuseAuthority `seq` pure ()
