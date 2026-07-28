module Main (main) where

import Infernix.Engines.AppleSilicon

main :: IO ()
main = hydrateCandidate `seq` pure ()
