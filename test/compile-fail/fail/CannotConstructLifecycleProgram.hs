module Main (main) where

import Infernix.Cluster (LifecycleProgram)

construct :: LifecycleProgram () ()
construct = FinishLifecycle ()

main :: IO ()
main = construct `seq` pure ()
