module Main (main) where

import Infernix.Config (Paths)
import Infernix.ExecutionPlan (CompiledRuntimePlan)
import Infernix.Runtime.Pulsar (drainTopic)

rawDrain ::
  Paths ->
  CompiledRuntimePlan ->
  IO ()
rawDrain = drainTopic

main :: IO ()
main = rawDrain `seq` pure ()
