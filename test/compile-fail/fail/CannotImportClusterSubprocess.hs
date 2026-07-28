module Main (main) where

import Infernix.Cluster.Subprocess (runBoundedCommand)

main :: IO ()
main = runBoundedCommand `seq` pure ()
