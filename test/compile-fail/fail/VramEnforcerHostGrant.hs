{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

mismatchedLaunch ::
  Enforcer 'NvidiaVram ->
  MemoryGrant 'HostRam ->
  ()
mismatchedLaunch = sameResource

sameResource :: Enforcer resource -> MemoryGrant resource -> ()
sameResource _ _ = ()

main :: IO ()
main = mismatchedLaunch `seq` pure ()
