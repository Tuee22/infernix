{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

matchingHost ::
  Enforcer 'HostRam ->
  MemoryGrant 'HostRam ->
  ()
matchingHost = sameResource

sameResource :: Enforcer resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = matchingHost `seq` pure ()
