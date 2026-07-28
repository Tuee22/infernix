module Main (main) where

import Data.Text (Text)
import DesiredApi

lookupBeforeRefinement ::
  Text ->
  CompiledRuntimePlan ->
  Maybe ExecutableModel
lookupBeforeRefinement = lookupExecutableModel

main :: IO ()
main = lookupBeforeRefinement `seq` pure ()
