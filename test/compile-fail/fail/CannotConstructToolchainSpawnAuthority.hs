module Main (main) where

import Infernix.BuildMemory (BuildMemoryPlan, ToolchainSpawnAuthority)

-- The authority's constructor is package internal, so a caller cannot mint
-- spawn authority from a plan it happens to hold.
forgeAuthority :: BuildMemoryPlan -> ToolchainSpawnAuthority s
forgeAuthority = ToolchainSpawnAuthority

main :: IO ()
main = pure ()
