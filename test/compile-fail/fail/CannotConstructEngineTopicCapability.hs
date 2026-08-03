-- The engine topic capability carries the execution authority, so forging one
-- would reattach a refined plan to a different token and defeat the
-- serialization the capability exists to carry.
module Main (main) where

import Infernix.Runtime.Pulsar (DaemonTopicCapability (EngineTopicCapability))

main :: IO ()
main = pure ()
