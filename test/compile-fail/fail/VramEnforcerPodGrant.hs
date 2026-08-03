{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

-- Phase 6 Sprint 6.44: a live NVIDIA VRAM enforcer may not be paired with the
-- pod resident-set grant that runs alongside it in a GPU placement. The two
-- grants are independently indexed, so substituting one for the other cannot
-- typecheck even though both halves are minted for the same placement.
mismatchedLaunch ::
  Enforcer 'NvidiaVram ->
  MemoryGrant 'PodRam ->
  ()
mismatchedLaunch = sameResource

sameResource :: Enforcer resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = mismatchedLaunch `seq` pure ()
