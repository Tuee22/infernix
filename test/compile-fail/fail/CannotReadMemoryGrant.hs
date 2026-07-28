{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

forgedGrant :: MemoryGrant 'HostRam
forgedGrant = read "MemoryGrant (MemoryCeiling 1)"

main :: IO ()
main = forgedGrant `seq` pure ()
