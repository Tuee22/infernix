module Main (main) where

import Infernix.Engines.AppleSilicon (materializeMetalEngineArtifact)

main :: IO ()
main = materializeMetalEngineArtifact `seq` pure ()
