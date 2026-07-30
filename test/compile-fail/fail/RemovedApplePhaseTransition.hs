module Main (main) where

import Infernix.Engines.AppleSilicon (hydrateCandidate)

main :: IO ()
main = hydrateCandidate `seq` pure ()
