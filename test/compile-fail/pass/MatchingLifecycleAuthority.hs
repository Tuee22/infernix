module Main (main) where

import Infernix.Cluster (ClusterMutationLocked, ClusterTeardownAuthority, clusterTeardownAuthorityRegionWitness)
import Infernix.Evidence.Lease (Lease)

preserve :: ClusterTeardownAuthority owner region -> ClusterTeardownAuthority owner region
preserve = id

matching :: Lease region ClusterMutationLocked -> ClusterTeardownAuthority owner region -> ()
matching = clusterTeardownAuthorityRegionWitness

main :: IO ()
main = preserve `seq` matching `seq` pure ()
