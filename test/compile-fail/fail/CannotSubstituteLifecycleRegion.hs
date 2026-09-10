module Main (main) where

import Data.Coerce (coerce)
import Infernix.Cluster (LifecycleSession)

data Original

data Replacement

substitute :: LifecycleSession Original -> LifecycleSession Replacement
substitute = coerce

main :: IO ()
main = substitute `seq` pure ()
