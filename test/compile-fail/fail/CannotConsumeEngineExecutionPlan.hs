-- The operation that opens the serialized execution region stays inside the
-- engine boundary. External callers can refine a plan but cannot consume its
-- enclosed execution authority directly.
module Main (main) where

import Infernix.Runtime.Enforcer (withEngineExecutionPlan)

main :: IO ()
main = pure ()
