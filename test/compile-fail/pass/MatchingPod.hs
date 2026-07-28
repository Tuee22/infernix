{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

matchingPod ::
  Enforcer 'PodRam ->
  MemoryGrant 'PodRam ->
  ()
matchingPod = sameResource

sameResource :: Enforcer resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = matchingPod `seq` pure ()
