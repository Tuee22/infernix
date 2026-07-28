{-# LANGUAGE DataKinds #-}

module Main (main) where

import Data.Coerce (coerce)
import DesiredApi

relabelGrant :: MemoryGrant 'HostRam -> MemoryGrant 'PodRam
relabelGrant = coerce

main :: IO ()
main = relabelGrant `seq` pure ()
