{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

launchWithPlanOnly ::
  EnforcerPlan 'HostRam ->
  MemoryGrant 'HostRam ->
  ()
launchWithPlanOnly = sameResource

sameResource :: Enforcer resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = launchWithPlanOnly `seq` pure ()
