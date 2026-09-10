module Main (main) where

import Infernix.Cluster (LifecycleSession)

construct :: LifecycleSession ()
construct = LifecycleSession

main :: IO ()
main = construct `seq` pure ()
