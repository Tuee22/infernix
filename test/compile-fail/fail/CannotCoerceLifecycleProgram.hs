module Main (main) where

import Data.Coerce (coerce)
import Infernix.Cluster (LifecycleProgram)

data Original

data Replacement

substitute :: LifecycleProgram Original () -> LifecycleProgram Replacement ()
substitute = coerce

main :: IO ()
main = substitute `seq` pure ()
