{-# LANGUAGE DataKinds #-}

-- | The positive control for the two Phase 4 Sprint 4.38 requirement fixtures: a
-- requirement paired with a grant for the /same/ resource compiles, so those
-- negative fixtures fail for the reason they name rather than for an unrelated
-- one.
module Main (main) where

import DesiredApi

matchingDevice ::
  ModelMemoryRequirement 'NvidiaVram ->
  MemoryGrant 'NvidiaVram ->
  ()
matchingDevice = sameResource

matchingHostResidency ::
  ModelMemoryRequirement 'HostRam ->
  MemoryGrant 'HostRam ->
  ()
matchingHostResidency = sameResource

sameResource :: ModelMemoryRequirement resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = matchingDevice `seq` matchingHostResidency `seq` pure ()
