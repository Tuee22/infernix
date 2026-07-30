module Main (main) where

import Infernix.Engines.AppleSilicon (MaterializationRequest)

main :: IO ()
main = print (show MaterializationRequest)
