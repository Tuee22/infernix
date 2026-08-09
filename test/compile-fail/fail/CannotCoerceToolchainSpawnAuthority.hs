module Main (main) where

import Data.Coerce (coerce)
import Infernix.BuildMemory (ToolchainSpawnAuthority)

-- The authority's region parameter is nominal. Coercion cannot turn a token
-- minted for one rank-2 region into permission in another region.
coerceAuthority ::
  ToolchainSpawnAuthority sourceRegion ->
  ToolchainSpawnAuthority targetRegion
coerceAuthority = coerce

main :: IO ()
main = pure ()
