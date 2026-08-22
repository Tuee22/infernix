{-# LANGUAGE DataKinds #-}

-- | Phase 4 Sprint 4.38: a model's requirement is indexed by the resource it is
-- a requirement for, with a nominal role, so a host quantity cannot be
-- relabelled into a device quantity. The positive control is
-- @pass\/MatchingRequirement.hs@.
module Main (main) where

import Data.Coerce (coerce)
import DesiredApi

relabelRequirement ::
  ModelMemoryRequirement 'HostRam ->
  ModelMemoryRequirement 'NvidiaVram
relabelRequirement = coerce

main :: IO ()
main = relabelRequirement `seq` pure ()
