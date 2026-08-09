module Main (main) where

import Data.Coerce (coerce)
import Infernix.BuildMemory (DarwinBuildMemoryValidationAuthority)

-- The Darwin refinement retains the nominal region of its underlying spawn
-- authority rather than reopening a representational-coercion escape.
coerceDarwinAuthority ::
  DarwinBuildMemoryValidationAuthority sourceRegion ->
  DarwinBuildMemoryValidationAuthority targetRegion
coerceDarwinAuthority = coerce

main :: IO ()
main = pure ()
