module Main (main) where

import Infernix.Engines.AppleSilicon

main :: IO ()
main = MaterializationRequest `seq` pure ()
