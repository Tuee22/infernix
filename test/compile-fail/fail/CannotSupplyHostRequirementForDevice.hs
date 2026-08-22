{-# LANGUAGE DataKinds #-}

-- | Phase 4 Sprint 4.38: a host requirement supplied where a device requirement
-- is demanded is not a term. This is the substitution the retired single scalar
-- made unremarkable — one @Int@ was compared against a host capacity and against
-- a device capacity, and the result was a correctly indexed grant either way.
-- The positive control is @pass\/MatchingRequirement.hs@.
module Main (main) where

import DesiredApi

deviceRequirement ::
  ModelMemoryRequirement 'HostRam ->
  ModelMemoryRequirement 'NvidiaVram
deviceRequirement = admitsDevice

admitsDevice ::
  ModelMemoryRequirement 'NvidiaVram ->
  ModelMemoryRequirement 'NvidiaVram
admitsDevice deviceValue = deviceValue

main :: IO ()
main = deviceRequirement `seq` pure ()
