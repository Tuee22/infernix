{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

-- Phase 6 Sprint 6.44: the reverse substitution is equally unrepresentable —
-- the Linux resident-set watchdog cannot be handed the VRAM grant and be
-- accepted as device enforcement.
mismatchedLaunch ::
  Enforcer 'PodRam ->
  MemoryGrant 'NvidiaVram ->
  ()
mismatchedLaunch = sameResource

sameResource :: Enforcer resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = mismatchedLaunch `seq` pure ()
