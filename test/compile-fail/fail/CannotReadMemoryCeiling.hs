{-# LANGUAGE DataKinds #-}

module Main (main) where

import DesiredApi

forgedCeiling :: MemoryCeiling 'HostRam
forgedCeiling = read "MemoryCeiling 1"

main :: IO ()
main = forgedCeiling `seq` pure ()
