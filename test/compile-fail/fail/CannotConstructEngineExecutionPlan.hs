-- A refined plan and its single-flight authority are one opaque value. A
-- caller cannot construct another copy around the same RuntimePlan and thereby
-- execute it under an independent lock.
module Main (main) where

import Infernix.Runtime.Enforcer (EngineExecutionPlan)

forgedExecutionPlan :: EngineExecutionPlan
forgedExecutionPlan = EngineExecutionPlan

main :: IO ()
main = forgedExecutionPlan `seq` pure ()
