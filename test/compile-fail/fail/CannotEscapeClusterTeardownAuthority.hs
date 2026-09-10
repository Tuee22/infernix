module Main (main) where

import Infernix.Cluster (ClusterTeardownAuthority)

-- Direct region erasure is forbidden independently of the effect-program tests.
escapeAuthority :: ClusterTeardownAuthority owner region -> ClusterTeardownAuthority owner ()
escapeAuthority authority = authority

main :: IO ()
main = escapeAuthority `seq` pure ()
