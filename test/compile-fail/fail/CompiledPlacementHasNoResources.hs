-- | Phase 4 Sprint 4.34: a compiled placement is graph validation only. It
-- holds no admitted resources, so the compile-time projection that used to read
-- them off a placement no longer exists at the public boundary.
module Main (main) where

import Infernix.ExecutionPlan (compiledPlacementEnforcedResources)

main :: IO ()
main = compiledPlacementEnforcedResources `seq` pure ()
