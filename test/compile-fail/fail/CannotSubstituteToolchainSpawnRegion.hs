module Main (main) where

import Infernix.BuildMemory
  ( BuildMemoryPlan,
    ToolchainSpawnAuthority,
    withToolchainSpawnAuthority,
  )

-- Two authorities from two regions do not share a tag, so one region's ceiling
-- cannot be substituted for another's.
sameRegion :: ToolchainSpawnAuthority s -> ToolchainSpawnAuthority s -> IO ()
sameRegion _ _ = pure ()

substituteRegion :: BuildMemoryPlan -> IO ()
substituteRegion plan =
  withToolchainSpawnAuthority plan $ \outer ->
    withToolchainSpawnAuthority plan $ \inner ->
      sameRegion outer inner

main :: IO ()
main = pure ()
