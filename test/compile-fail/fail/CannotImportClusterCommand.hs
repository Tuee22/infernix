module Main (main) where

import Infernix.Cluster.Command (kindDelete)

main :: IO ()
main = kindDelete `seq` pure ()
