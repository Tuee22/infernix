{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

forgedGrant :: MemoryGrant 'HostRam
forgedGrant = MemoryGrant (undefined :: MemoryCeiling 'HostRam)

main :: IO ()
main = forgedGrant `seq` pure ()
